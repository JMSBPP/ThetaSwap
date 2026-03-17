# Architecture Research

**Domain:** Rust CLI tool wrapping external processes (forge/cast), embedded in a Foundry monorepo
**Researched:** 2026-03-17
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        CLI Entry Layer                           │
│   main.rs: parse args with clap, dispatch to command handler    │
├──────────────────────────────────────────────────────────────────┤
│                      Command Layer                               │
│  ┌───────────────────┐      ┌──────────────────────────────┐    │
│  │   Cli struct       │      │   Commands enum              │    │
│  │  (global flags)   │─────▶│   ts::reactive::Protocol     │    │
│  └───────────────────┘      └──────────────┬───────────────┘    │
├─────────────────────────────────────────────┼────────────────────┤
│                     Execution Layer          │                   │
│  ┌───────────────────┐      ┌───────────────▼──────────────┐    │
│  │  deploy::primary  │      │   deploy::Runner             │    │
│  │  (forge create)   │◀─────│   tries primary, falls back  │    │
│  └───────────────────┘      └───────────────┬──────────────┘    │
│  ┌───────────────────┐                       │                   │
│  │  deploy::fallback │◀──────────────────────┘                  │
│  │  (cast send       │                                           │
│  │   --create)       │                                           │
│  └───────────────────┘                                           │
├──────────────────────────────────────────────────────────────────┤
│                    Output/Error Layer                            │
│  ┌──────────────┐   ┌──────────────┐   ┌─────────────────────┐  │
│  │  stdout      │   │  stderr      │   │  exit code          │  │
│  │  addr + hash │   │  error msg   │   │  0 = ok, 1 = fail   │  │
│  └──────────────┘   └──────────────┘   └─────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
         ↑ PATH lookup
┌────────┴──────────────┐
│   External processes  │
│   forge   cast        │
│   (Foundry toolchain) │
└───────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|---------------|----------------|
| `main.rs` | Entry point: parse Cli, match command variant, propagate errors with anyhow | `fn main() -> anyhow::Result<()>` |
| `Cli` struct | Global flags: `--rpc-url`, `--private-key`; subcommand field | `#[derive(Parser)]` clap struct |
| `Commands` enum | Top-level subcommand routing: `Ts(TsArgs)` | `#[derive(Subcommand)]` enum |
| `TsArgs` | Mid-level: `reactive` subcommand | `#[derive(Args)]` struct with nested `#[command(subcommand)]` |
| `ReactiveArgs` | Leaf command: `uniswap-v3` protocol selector + `--callback`, `--value` | `#[derive(Args)]` struct |
| `deploy::Runner` | Orchestrates primary attempt then fallback; owns the try-fallback logic | Plain struct, methods return `anyhow::Result<DeployOutput>` |
| `deploy::primary` | Builds and runs `forge create` command; parses address + tx hash from stdout | `fn run(...) -> anyhow::Result<DeployOutput>` |
| `deploy::fallback` | Builds and runs `cast send --create`; parses address + tx hash from stdout | `fn run(...) -> anyhow::Result<DeployOutput>` |
| `output::DeployOutput` | Typed result: `address: String`, `tx_hash: String` | Plain struct, `Display` impl for pipe-friendly printing |
| `errors::D2pError` | Domain error enum covering process-not-found, non-zero exit, parse failure | `#[derive(thiserror::Error)]` — used inside `deploy::` modules |

## Recommended Project Structure

```
d2p/                       # Rust CLI crate root — lives alongside foundry.toml
├── Cargo.toml             # [package] d2p; no workspace needed for single crate
├── src/
│   ├── main.rs            # Entry point: parse Cli, match Commands, print DeployOutput
│   ├── cli.rs             # Cli struct, Commands enum, TsArgs, ReactiveArgs, Protocol enum
│   ├── deploy/
│   │   ├── mod.rs         # DeployParams (shared input), DeployOutput (shared result), Runner
│   │   ├── primary.rs     # forge create invocation + output parsing
│   │   └── fallback.rs    # cast send --create invocation + output parsing
│   ├── output.rs          # DeployOutput Display impl (address\ntx_hash), error formatting
│   └── errors.rs          # D2pError enum (thiserror) — process, parse, non-zero exit
└── tests/
    └── integration.rs     # Smoke tests calling d2p binary with mock forge/cast on PATH
```

### Structure Rationale

- **`d2p/` at repo root**: Keeps the Rust crate isolated from Foundry's directory layout. A `Cargo.toml` at `d2p/` is self-contained; no root virtual manifest needed because there is only one Rust crate. The existing `foundry.toml` at repo root is unaffected.
- **`deploy/` module split**: `primary.rs` and `fallback.rs` are separate files so the try-fallback logic in `Runner` stays readable and each strategy can be tested independently.
- **`cli.rs` isolated**: Keeps all clap derive code in one place; `main.rs` stays to a few lines of match dispatch.
- **`errors.rs` with `thiserror`**: `deploy::` modules return typed `D2pError`; `main.rs` uses `anyhow` to attach context and print to stderr.

## Architectural Patterns

### Pattern 1: Clap Derive with Nested Subcommand Enums

**What:** Each level of the subcommand hierarchy is a separate enum or struct. `Cli` holds `Commands`; `Commands::Ts` holds `TsArgs`; `TsArgs` holds `ReactiveCommands`; leaves hold flag structs. Each type derives what it needs (`Parser`, `Subcommand`, `Args`).

**When to use:** Always — this is the idiomatic clap 4.x derive pattern. Avoids the builder API which is verbose and not type-checked.

**Trade-offs:** More types to define upfront; pays off immediately when adding a second subcommand (structure already exists).

**Example:**
```rust
#[derive(Parser)]
#[command(name = "d2p")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// ThetaSwap contract deployment
    Ts(TsArgs),
}

#[derive(Args)]
struct TsArgs {
    #[command(subcommand)]
    command: TsCommands,
}

#[derive(Subcommand)]
enum TsCommands {
    /// Deploy a reactive contract
    Reactive(ReactiveArgs),
}

#[derive(Args)]
struct ReactiveArgs {
    /// Protocol to deploy (uniswap-v3)
    protocol: Protocol,
    #[arg(long)] callback: String,
    #[arg(long)] rpc_url: String,
    #[arg(long)] private_key: String,
    #[arg(long, default_value = "0")] value: String,
}
```

### Pattern 2: Try-Primary / Fallback Runner

**What:** A `Runner` struct holds the deploy parameters and exposes a single `deploy()` method that calls `primary::run()`. If primary returns an error (any error — non-zero exit, parse failure, process not found), it logs a warning to stderr and immediately calls `fallback::run()`. If fallback also fails, it returns the fallback error.

**When to use:** Exactly this case — `forge create` has a known RPC-url bug; `cast send --create` is the reliable path. The fallback must be transparent to callers.

**Trade-offs:** Hides failure mode of primary; worth it because primary's failure mode is silent/wrong not loud/clear. Add a `--no-fallback` flag only if debugging becomes painful.

**Example:**
```rust
impl Runner {
    pub fn deploy(&self) -> anyhow::Result<DeployOutput> {
        match primary::run(&self.params) {
            Ok(out) => Ok(out),
            Err(e) => {
                eprintln!("forge create failed ({e}), trying cast send --create");
                fallback::run(&self.params)
            }
        }
    }
}
```

### Pattern 3: Captured Output Parsing from Child Process

**What:** Spawn the child process with `std::process::Command`, call `.output()` (not `.status()`) to capture both stdout and stderr as `Vec<u8>`. Check `output.status.success()`. Parse address and tx hash from stdout using string search or a minimal regex.

**When to use:** Whenever the output of a subprocess is the primary result, not just its success/failure. `.output()` buffers both streams to memory — safe for the small outputs forge/cast produce.

**Trade-offs:** `.output()` buffers everything in memory before returning, which is correct for forge/cast (output is small). For large outputs (e.g., logs), prefer streaming with `.spawn()` + reading from `child.stdout`. Do not use streaming here — it adds complexity for no gain.

**Example:**
```rust
fn run(params: &DeployParams) -> anyhow::Result<DeployOutput> {
    let out = std::process::Command::new("forge")
        .args(build_args(params))
        .output()
        .context("forge not found on PATH")?;

    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        anyhow::bail!("forge create exited non-zero: {stderr}");
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    parse_deploy_output(&stdout)
}
```

## Data Flow

### Primary Deploy Flow

```
User invokes: d2p ts reactive uniswap-v3 --callback 0x... --rpc-url ... --private-key ...
    |
    v
main() parses Cli with clap::Parser::parse()
    |
    v
match Commands::Ts -> TsCommands::Reactive(args)
    |
    v
Runner::new(DeployParams::from(args))
    |
    v
primary::run(params)
    |--- builds: ["forge", "create", "src/...", "--rpc-url", ..., "--broadcast", "--legacy",
    |             "--constructor-args", args.callback, "--value", args.value]
    |
    v
std::process::Command::new("forge").args(...).output()
    |
    +-- success? --> parse stdout for "Deployed to: 0x..." and "Transaction hash: 0x..."
    |                    |
    |                    v
    |               DeployOutput { address, tx_hash }
    |                    |
    |                    v
    |               println!("{}\n{}", out.address, out.tx_hash)  -> stdout
    |                    |
    |                    v
    |               process::exit(0)
    |
    +-- failure? --> eprintln!("forge create failed, trying fallback") -> stderr
                        |
                        v
                    fallback::run(params)
                        |--- builds: ["cast", "send", "--create", <bytecode>, <encoded-args>,
                        |             "--rpc-url", ..., "--private-key", ..., "--legacy",
                        |             "--value", args.value]
                        |
                        v
                    std::process::Command::new("cast").args(...).output()
                        |
                        +-- success? --> parse, print, exit(0)
                        +-- failure? --> eprintln!(error) -> stderr, exit(1)
```

### Key Data Flows

1. **Flags to DeployParams:** All clap-parsed flags (rpc_url, private_key, callback, value, protocol) are collected into a single `DeployParams` struct before touching `deploy::`. This means `cli.rs` depends on `deploy::DeployParams` but `deploy::` has no dependency on clap.

2. **Child process stdout to DeployOutput:** forge/cast stdout is captured as bytes, decoded as UTF-8 (lossy), scanned for known output patterns. The address line and tx hash line are extracted by prefix matching ("Deployed to:", "Transaction hash:") — more robust than regex for this narrow case.

3. **Errors upward:** `D2pError` (thiserror) bubbles from `deploy::` into `Runner::deploy()`. `main()` uses `anyhow::Result` — if both paths fail, `anyhow` prints the chained error to stderr and main returns a non-zero exit code.

## Scaling Considerations

This is a CLI tool, not a server. "Scaling" means: adding more subcommands without structural debt.

| Concern | Now (1 protocol) | Later (N protocols) |
|---------|-----------------|---------------------|
| Protocol dispatch | `Protocol` enum with `UniswapV3` variant | Add variant, add arm in `deploy::` match |
| New subcommands (`d2p ts cfmm`) | `TsCommands` enum has one variant | Add variant to enum, add handler module |
| New top-level commands (`d2p verify`) | `Commands` enum has one variant | Add variant, the structure already supports it |
| Output formats | Plain `address\nhash` | Add `--output json` flag later; `DeployOutput` already a struct |

The nested enum pattern in clap means new commands never require touching existing command structs — only the parent enum grows.

## Anti-Patterns

### Anti-Pattern 1: Calling `forge` / `cast` via shell string interpolation

**What people do:** `Command::new("sh").arg("-c").arg(format!("forge create {} ...", contract))` to avoid building the args array.

**Why it's wrong:** Shell injection risk when any argument contains spaces or special characters. Private keys, addresses, and RPC URLs frequently contain characters that break naive quoting. Also defeats the purpose of `Command::new` which handles argument escaping correctly.

**Do this instead:** Build a `Vec<&str>` (or `Vec<String>`) of arguments and pass each element individually to `.arg()` or `.args()`. The OS-level `execve` call never interprets shell metacharacters.

### Anti-Pattern 2: Using a root-level `Cargo.toml` virtual workspace manifest

**What people do:** Add a `[workspace]` to the repo root `Cargo.toml` to "integrate" the Rust tool with the rest of the repo.

**Why it's wrong:** The repo root has no `Cargo.toml` — adding one there could confuse Cargo's automatic workspace discovery when running `cargo` from any subdirectory. A virtual manifest at repo root also gives the impression the whole repo is a Rust project, conflicting with Foundry's ownership of the root `foundry.toml`.

**Do this instead:** Keep `d2p/Cargo.toml` self-contained at `d2p/`. Running `cargo build --manifest-path d2p/Cargo.toml` or simply `cd d2p && cargo build` is the correct invocation. Document this in the project README. Foundry and Cargo coexist without interference when their roots are separate.

### Anti-Pattern 3: Parsing forge/cast output with fragile regex on full stdout

**What people do:** Write a regex like `r"0x[a-fA-F0-9]{40}"` against all of stdout to find the deployed address.

**Why it's wrong:** forge/cast output contains multiple hex strings (constructor args, etc.). The first match is not guaranteed to be the contract address. Output format can also change across Foundry versions.

**Do this instead:** Find the specific labeled line first ("Deployed to:" or "Contract Address:"), then take the value from that line. This is prefix-matching, not open-ended pattern matching, and is stable against output that contains other hex values.

### Anti-Pattern 4: Single `main.rs` file for everything

**What people do:** Put Cli struct, command handling, process invocation, and output parsing all in `main.rs`.

**Why it's wrong:** Makes testing impossible without spawning the binary. Parsing logic and process invocation cannot be unit-tested in isolation.

**Do this instead:** `main.rs` is 20–40 lines: parse args, call one function, handle the result. All logic lives in modules that can be tested with `cargo test`.

## Integration Points

### External Processes

| Process | Integration Pattern | Notes |
|---------|---------------------|-------|
| `forge create` | `std::process::Command`, `.output()`, check exit status | Must be on PATH; primary deploy path |
| `cast send --create` | `std::process::Command`, `.output()`, check exit status | Fallback path; requires bytecode as hex arg |
| Foundry build (`forge build`) | Not called by d2p directly — user must run before deploying | d2p assumes compiled artifacts exist; does not trigger compilation |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `cli.rs` → `deploy::` | `DeployParams` struct — plain data, no clap types | Keeps deploy logic testable without clap |
| `deploy::Runner` → `primary`/`fallback` | Function call returning `anyhow::Result<DeployOutput>` | Runner owns the fallback decision; strategies are pure functions |
| `deploy::` → `main.rs` | `DeployOutput` or `anyhow::Error` | main only does printing and exit code; no business logic |
| `d2p/` → Foundry repo | Reads `foundry.toml` indirectly (forge reads it); d2p itself does not parse it | Compilation is the user's responsibility before invoking d2p |

## Suggested Build Order

1. **`errors.rs` + `output.rs`** — Define `D2pError` and `DeployOutput` first. No dependencies. All other modules depend on these types.

2. **`deploy/mod.rs`** — Define `DeployParams` struct. Depends on `errors.rs` and `output.rs`. Establishes the interface between CLI and deploy logic.

3. **`deploy/primary.rs`** — Implement `forge create` invocation and stdout parsing. Depends on `DeployParams`, `DeployOutput`, `D2pError`. Testable in isolation with a mock `forge` binary.

4. **`deploy/fallback.rs`** — Implement `cast send --create`. Same interface as primary. Testable independently.

5. **`deploy/mod.rs` Runner** — Implement `Runner::deploy()` with try-primary-then-fallback. Depends on both strategy modules.

6. **`cli.rs`** — Define all clap structs and enums. Depends on `DeployParams` to convert args. No process invocation.

7. **`main.rs`** — Wire everything together. Depends on all above. The last file to touch.

8. **`tests/integration.rs`** — End-to-end smoke test invoking the compiled binary. Written after the binary compiles.

## Sources

- [Handling arguments — Rain's Rust CLI recommendations](https://rust-cli-recommendations.sunshowers.io/handling-arguments.html) — MEDIUM confidence (WebSearch verified against clap docs)
- [clap derive tutorial — docs.rs](https://docs.rs/clap/latest/clap/_derive/_tutorial/index.html) — HIGH confidence (official documentation)
- [Communicating with machines — Command Line Applications in Rust](https://rust-cli.github.io/book/in-depth/machine-communication.html) — HIGH confidence (official Rust CLI book)
- [Exit codes — Command Line Applications in Rust](https://rust-cli.github.io/book/in-depth/exit-code.html) — HIGH confidence (official Rust CLI book)
- [std::process::Command — Rust stdlib](https://doc.rust-lang.org/std/process/struct.Command.html) — HIGH confidence (official stdlib docs)
- [anyhow — dtolnay/anyhow](https://github.com/dtolnay/anyhow) — HIGH confidence (official crate)
- [thiserror and anyhow — Comprehensive Rust](https://google.github.io/comprehensive-rust/error-handling/thiserror-and-anyhow.html) — HIGH confidence (Google/official)
- [Cargo Workspaces — The Cargo Book](https://doc.rust-lang.org/cargo/reference/workspaces.html) — HIGH confidence (official Cargo docs)

---
*Architecture research for: Rust CLI process-wrapper (d2p) in Foundry monorepo*
*Researched: 2026-03-17*
