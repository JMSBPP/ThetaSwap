# Phase 3: CLI Wiring - Research

**Researched:** 2026-03-18
**Domain:** clap 4.x derive API — nested subcommands, env fallbacks, value parsing, exit code control
**Confidence:** HIGH

## Summary

Phase 3 is mechanical wiring: all deploy logic is complete in `deploy/`. The sole task is defining clap structs that parse `d2p ts reactive uniswap-v3 [flags]` and converting parsed args into a `DeployParams` struct that `Runner::deploy()` consumes. The Phase 2 output contract (`DeployParams`, `DeployOutput`, `D2pError`) is the stable API surface — `cli.rs` depends on it; `deploy/` has zero knowledge of clap.

Two non-trivial concerns exist: (1) `--value` requires human-friendly unit parsing ("10react", "0.01ether") rather than raw wei — this is a small custom `FromStr` impl, not a third-party crate; (2) env var fallback via `#[arg(env = "ETH_RPC_URL")]` requires adding the `"env"` feature to clap in Cargo.toml — this feature is NOT currently present and the code will fail to compile without it.

**Primary recommendation:** Add `"env"` to clap's features list first. Then create `cli.rs` with the nested derive hierarchy, implement `parse_value()` as a free function with unit tests, and wire `main.rs` to ~30 lines that call `Cli::parse()`, construct `DeployParams`, and print `DeployOutput` or exit 1.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CMD-01 | `d2p ts reactive uniswap-v3` subcommand tree | clap nested `Subcommand` + `Args` enums; Protocol enum with `UniswapV3` variant |
| CMD-02 | `--rpc-url` with `ETH_RPC_URL` env fallback | `#[arg(long, env = "ETH_RPC_URL")]` — requires clap `"env"` feature |
| CMD-03 | `--private-key` with `ETH_PRIVATE_KEY` env fallback | `#[arg(long, env = "ETH_PRIVATE_KEY")]` — same feature requirement |
| CMD-04 | `--callback` required, no default | `#[arg(long)]` with no `default_value`; clap enforces required by default for non-Option fields |
| CMD-05 | `--value` human unit parsing ("10react", "0.01ether"), default "10react" | Custom `parse_value()` free function; `default_value = "10react"` |
| CMD-06 | `--legacy` baked in, not user-supplied | No `--legacy` flag in clap struct; hard-coded in `primary.rs` build_args already |
| CMD-07 | `--help` shows usage with examples | `#[command(long_about = "...")]` on `ReactiveArgs`; clap generates `--help` automatically |
| CMD-08 | `d2p --version` shows Cargo.toml version | `#[command(version)]` on top-level `Cli` struct |
| CMD-09 | `--project` for Solidity root, defaults to CWD | `#[arg(long, default_value = ".")]` with `PathBuf` type; `canonicalize()` in main |
| OUT-02 | Stderr shows attempted command and error on failure | `anyhow` chain in `main()`: `eprintln!("{:?}", err)` or the default anyhow error chain |
| OUT-03 | Exit code 0 on success, 1 on failure | `std::process::exit(1)` in error arm of `main()`, or `fn main() -> anyhow::Result<()>` with `process::exit` wrapper |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| clap | 4.6.0 (resolved) | Argument parsing, subcommand routing, env fallbacks | Already in Cargo.toml; derive feature already active; env feature needed |
| anyhow | 1.0.102 | Error propagation in main(), error formatting to stderr | Already in Cargo.toml; `fn main() -> anyhow::Result<()>` is idiomatic |
| std::path::PathBuf | stdlib | `--project` flag type | PathBuf handles path normalization; used in DeployParams.project_dir already |
| std::env | stdlib | CWD default for `--project` | `std::env::current_dir()` for PathBuf::from(".") canonicalization |

### No New Dependencies Required

All libraries needed for Phase 3 are already in Cargo.toml. The only Cargo.toml change needed is adding `"env"` to clap's feature list.

**Required Cargo.toml change:**
```toml
clap = { version = "4.5", features = ["derive", "env"] }
```

**Version note (verified via `cargo tree`):** The currently-resolved clap version is 4.6.0, higher than the `"4.5"` spec in Cargo.toml. This is normal semver resolution. No version bump is needed in Cargo.toml — only the feature list change.

## Architecture Patterns

### Recommended File Layout (Phase 3 adds one file)

```
d2p/src/
├── main.rs          # MODIFY: wire Cli::parse() → DeployParams → Runner::deploy() → print/exit
├── cli.rs           # CREATE: all clap structs and Protocol enum
├── deploy/
│   ├── mod.rs       # EXISTS: DeployParams, DeployOutput, Runner — no changes
│   ├── primary.rs   # EXISTS: forge create — no changes
│   ├── fallback.rs  # EXISTS: cast send --create — no changes
│   └── verify.rs    # EXISTS: cast receipt — no changes
└── errors.rs        # EXISTS: D2pError — no changes
```

Only `main.rs` and the new `cli.rs` are touched in Phase 3. Zero modifications to `deploy/` or `errors.rs`.

### Pattern 1: Clap Nested Subcommand Hierarchy (derive)

**What:** Each level of the command tree is a separate type. `Cli` holds `Commands`; `Commands::Ts` holds `TsArgs`; `TsArgs` holds `TsCommands`; `TsCommands::Reactive` holds `ReactiveArgs`. Leaf structs carry the actual flags.

**When to use:** Always for static command trees. Avoids builder API verbosity.

**Verified example (from clap docs + edge-rs in-repo reference):**
```rust
// Source: clap derive tutorial docs.rs + tmp/edge-rs/bin/edgec/src/cli.rs
use clap::{Args, Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "d2p", version, about = "ThetaSwap deployment tool")]
#[command(arg_required_else_help = true)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Deploy ThetaSwap contracts
    Ts(TsArgs),
}

#[derive(Args)]
pub struct TsArgs {
    #[command(subcommand)]
    pub command: TsCommands,
}

#[derive(Subcommand)]
pub enum TsCommands {
    /// Deploy a reactive contract
    Reactive(ReactiveArgs),
}

#[derive(Args)]
pub struct ReactiveArgs {
    /// Protocol to deploy (uniswap-v3)
    pub protocol: Protocol,

    /// Ethereum RPC URL
    #[arg(long, env = "ETH_RPC_URL")]
    pub rpc_url: String,

    /// Ethereum private key (hex, 0x-prefixed)
    #[arg(long, env = "ETH_PRIVATE_KEY")]
    pub private_key: String,

    /// Callback proxy contract address
    #[arg(long)]
    pub callback: String,

    /// Value to send with deployment (e.g. "10react", "0.01ether")
    #[arg(long, default_value = "10react")]
    pub value: String,

    /// Solidity project root (forge build artifacts must exist here)
    #[arg(long, default_value = ".")]
    pub project: PathBuf,
}

#[derive(Clone, ValueEnum)]
pub enum Protocol {
    #[value(name = "uniswap-v3")]
    UniswapV3,
}
```

### Pattern 2: Protocol to contract_path Mapping

**What:** The `Protocol` enum variant determines `contract_path`. This mapping lives in `cli.rs` or a helper called by `main.rs` when constructing `DeployParams`.

**Mapping (confirmed from existing code and REQUIREMENTS):**
```rust
// Source: d2p/src/deploy/primary.rs test_params() + REQUIREMENTS.md CMD-01
fn contract_path_for(protocol: &Protocol) -> &'static str {
    match protocol {
        Protocol::UniswapV3 => {
            "src/fee-concentration-index-v2/protocols/uniswap-v3/UniswapV3Reactive.sol:UniswapV3Reactive"
        }
    }
}
```

**Key insight:** The contract name extracted from this path (`UniswapV3Reactive`) drives the artifact lookup in `fallback.rs::read_bytecode()`. The path format `src/path/to/File.sol:ContractName` is what forge create expects and what the fallback uses to find `out/UniswapV3Reactive.sol/UniswapV3Reactive.json`.

### Pattern 3: Value Unit Parsing (CMD-05)

**What:** `--value` accepts human-friendly strings like "10react", "0.01ether", "1000000000gwei". These are passed verbatim to forge create `--value` and cast send `--value` — Foundry handles the unit conversion. d2p's role is only to validate that the input is well-formed (has a numeric prefix and a known unit suffix) and to provide a clear error when it is not.

**Implementation:** A free function `parse_value(s: &str) -> Result<String, String>` used as a clap `value_parser`. Returns the string unchanged if valid; returns a descriptive error string otherwise.

**Units to accept (from CMD-05):** `react`, `ether`, `gwei`, `wei` — plus numeric prefix. The default is `"10react"`.

```rust
// Free function — no struct, no library needed
fn parse_value(s: &str) -> Result<String, String> {
    // Acceptable: any decimal number (int or float) followed by known unit
    let units = ["react", "ether", "gwei", "wei"];
    for unit in units {
        if let Some(num_str) = s.strip_suffix(unit) {
            if !num_str.is_empty() && num_str.parse::<f64>().is_ok() {
                return Ok(s.to_string());
            }
        }
    }
    Err(format!(
        "invalid value '{s}': expected <number><unit> where unit is one of: {}",
        units.join(", ")
    ))
}
```

**Usage in clap struct:**
```rust
#[arg(long, default_value = "10react", value_parser = parse_value)]
pub value: String,
```

### Pattern 4: Exit Code Discipline (OUT-03)

**What:** `fn main() -> anyhow::Result<()>` exits with code 1 automatically when it returns `Err`. However, the default anyhow error display sends the error chain to stderr — which satisfies OUT-02. For clean exit code 1, the idiomatic pattern is:

```rust
fn main() {
    if let Err(e) = run() {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();
    // ... dispatch ...
    Ok(())
}
```

**Why not `fn main() -> anyhow::Result<()>` directly:** anyhow's default error printing includes "Error: " prefix which may confuse scripts. Using `eprintln!("error: {e:#}")` gives full control over the stderr message format. Both patterns exit with code 1 on error — preference is the `run()` split for testability.

**Alternative (simpler):** `fn main() -> anyhow::Result<()>` is acceptable if the anyhow stderr format is fine. The REQUIREMENTS say "stderr shows which command was attempted and what went wrong" (OUT-02). anyhow's `{e:#}` format (the `#` pretty-prints the error chain) satisfies this.

### Pattern 5: --project PathBuf Canonicalization

**What:** `--project` defaults to `"."` which is the string CWD relative path. The `DeployParams.project_dir` field is a `PathBuf`. The conversion must canonicalize to an absolute path since child processes (forge, cast) are spawned with `current_dir(&params.project_dir)`.

```rust
let project_dir = args.project.canonicalize()
    .with_context(|| format!("project path does not exist: {}", args.project.display()))?;
```

**Pitfall:** `.canonicalize()` fails if the path does not exist. Since the default is `"."` (CWD), this will only fail if the user specifies a non-existent path. This is the correct behavior — fail fast before attempting forge commands.

### Anti-Patterns to Avoid

- **Putting flag logic in deploy/:** `cli.rs` converts CLI args to `DeployParams`; `deploy/` modules are clap-free. Never add `clap` imports to `deploy/`.
- **Using `std::env::var()` manually for env fallback:** clap `#[arg(env = "...")]` handles the precedence (flag overrides env) automatically. Manual `env::var()` with a fallback chain is redundant and error-prone.
- **Accepting raw wei for `--value`:** Users deploying to Lasna provide values in `react` units. Accepting only `wei` forces users to compute large numbers. Keep human units — pass the string to Foundry as-is.
- **`Commands` enum with a catchall arm:** All subcommand dispatch must be exhaustive. No `_ => unreachable!()` arms — clap ensures only valid variants reach the match.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Env var fallback with precedence | Manual `env::var()` + Option chaining | `#[arg(env = "ETH_RPC_URL")]` | clap handles flag-overrides-env precedence; manual code inverts it accidentally |
| Version string | Hardcoded version string | `#[command(version)]` on Cli | clap reads `CARGO_PKG_VERSION` at compile time — always matches Cargo.toml |
| Subcommand routing | Manual `args[0]` string matching | `#[derive(Subcommand)]` enum | clap generates help text, error messages, and shell completions for free |
| `--help` text | Custom help formatter | `#[command(long_about = "...")]` docstrings | clap composes help from doc comments on each field and struct |

**Key insight:** Phase 3 is ~100 lines of code total. Every line that fights clap's derive system is a line that could have been a doc comment.

## Common Pitfalls

### Pitfall 1: Missing clap `env` Feature
**What goes wrong:** `#[arg(env = "ETH_RPC_URL")]` silently compiles without the feature but **does not read env vars at runtime**. The env attribute is simply ignored when the feature is off. Users set `ETH_RPC_URL` and wonder why `--rpc-url` is still required.

**Why it happens:** clap gates env var reading behind a compile-time feature to keep binary size down for crates that don't need it.

**How to avoid:** Add `"env"` to clap's features list in Cargo.toml before writing a single `#[arg(env = ...)]` attribute. Verify with `cargo tree -f '{p} {f}'` that clap shows the env feature.

**Warning signs:** Missing `--rpc-url` flag error even when `ETH_RPC_URL` is set in the shell.

### Pitfall 2: Wrong clap Derive for Mid-Level Structs
**What goes wrong:** Using `#[derive(Parser)]` instead of `#[derive(Args)]` on `TsArgs` (the middle struct). `Parser` is for top-level binary entry structs only. `Args` is for structs embedded in an enum variant.

**Why it happens:** Both `Parser` and `Args` look similar; the error message from clap when misused is not immediately obvious.

**How to avoid:** Rule: only the top-level `Cli` struct derives `Parser`. Every embedded struct derives `Args`. Every enum of subcommands derives `Subcommand`.

### Pitfall 3: `Protocol` as Free String vs. `ValueEnum`
**What goes wrong:** Defining `protocol` as `String` instead of a `ValueEnum`. This means `d2p ts reactive bad-protocol` silently runs with `bad-protocol` and produces a panic or an obscure error in `contract_path_for()`.

**Why it happens:** Using `String` is the path of least resistance.

**How to avoid:** Always use `#[derive(ValueEnum)]` for protocol/variant arguments. clap generates the allowed-values list in `--help` and produces a clear error for unknown variants.

**Warning signs:** No mention of "uniswap-v3" in `d2p ts reactive --help` output.

### Pitfall 4: default_value for PathBuf Must Be a String Literal
**What goes wrong:** `#[arg(long, default_value = PathBuf::from("."))]` does not compile. `default_value` takes a `&str`, not a typed value.

**How to avoid:** Use `default_value = "."` (string). clap parses it through the `PathBuf` `FromStr` impl at runtime.

### Pitfall 5: Forgetting to Strip ETH_PRIVATE_KEY from Child Environment
**What goes wrong:** The child `forge`/`cast` processes may inherit `ETH_PRIVATE_KEY` from the calling environment if set, causing unexpected signing. `primary.rs` already calls `.env_remove("ETH_RPC_URL")` but `ETH_PRIVATE_KEY` is not explicitly stripped — it is passed explicitly via `--private-key`, so the subprocess value is overridden. This is not a regression; it is a pre-existing non-issue. But the env_remove pattern should not be extended incorrectly.

**How to avoid:** Leave `primary.rs` and `fallback.rs` unchanged. The explicit `--private-key` flag in the forge/cast arg vectors overrides any inherited env var. Do not add `env_remove("ETH_PRIVATE_KEY")` unless Foundry ignores the explicit flag (unconfirmed).

### Pitfall 6: Value Parser Must Return `String`, Not a Custom Type
**What goes wrong:** Defining `value_parser = parse_value` where `parse_value` returns a custom struct causes a type mismatch with the `pub value: String` field.

**How to avoid:** `parse_value(s: &str) -> Result<String, String>` — input and output are both `String`. The clap `value_parser` signature for `String` fields must return `Result<String, _>`. clap maps the error string to a `clap::Error`.

## Code Examples

Verified patterns from official sources and in-repo reference:

### Minimal cli.rs (complete, verified structure)
```rust
// Source: clap derive tutorial (docs.rs/clap/latest) + edge-rs/bin/edgec/src/cli.rs
use clap::{Args, Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "d2p", version, about = "ThetaSwap reactive contract deployment tool")]
#[command(arg_required_else_help = true)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand)]
pub enum Commands {
    /// Deploy ThetaSwap contracts
    Ts(TsArgs),
}

#[derive(Args)]
pub struct TsArgs {
    #[command(subcommand)]
    pub command: TsCommands,
}

#[derive(Subcommand)]
pub enum TsCommands {
    /// Deploy a reactive contract
    Reactive(ReactiveArgs),
}

#[derive(Args)]
#[command(long_about = "Deploy a reactive contract.\n\nExample:\n  d2p ts reactive uniswap-v3 \\\n    --rpc-url https://rpc.sepolia.org \\\n    --private-key $ETH_PRIVATE_KEY \\\n    --callback 0x...")]
pub struct ReactiveArgs {
    /// Protocol to deploy
    pub protocol: Protocol,
    /// Ethereum JSON-RPC endpoint
    #[arg(long, env = "ETH_RPC_URL")]
    pub rpc_url: String,
    /// Hex-encoded private key (0x-prefixed)
    #[arg(long, env = "ETH_PRIVATE_KEY")]
    pub private_key: String,
    /// Callback proxy contract address
    #[arg(long)]
    pub callback: String,
    /// Value to send with deployment (e.g. "10react", "0.01ether")
    #[arg(long, default_value = "10react", value_parser = parse_value)]
    pub value: String,
    /// Solidity project root (must contain forge build output in out/)
    #[arg(long, default_value = ".")]
    pub project: PathBuf,
}

#[derive(Clone, ValueEnum)]
pub enum Protocol {
    #[value(name = "uniswap-v3")]
    UniswapV3,
}

fn parse_value(s: &str) -> Result<String, String> {
    let units = ["react", "ether", "gwei", "wei"];
    for unit in units {
        if let Some(num_str) = s.strip_suffix(unit) {
            if !num_str.is_empty() && num_str.parse::<f64>().is_ok() {
                return Ok(s.to_string());
            }
        }
    }
    Err(format!(
        "invalid value '{}': expected <number><unit>, unit one of: {}",
        s,
        units.join(", ")
    ))
}
```

### main.rs (complete, ~30 lines)
```rust
// Source: anyhow crate docs + exit code pattern from Rust CLI Book
mod cli;
mod deploy;
mod errors;

use anyhow::Context;
use clap::Parser;
use cli::{Cli, Commands, Protocol, TsCommands};
use deploy::{DeployParams, Runner};

fn main() {
    if let Err(e) = run() {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Ts(ts) => match ts.command {
            TsCommands::Reactive(args) => {
                let contract_path = match args.protocol {
                    Protocol::UniswapV3 => "src/fee-concentration-index-v2/protocols/uniswap-v3/UniswapV3Reactive.sol:UniswapV3Reactive",
                };
                let project_dir = args.project.canonicalize()
                    .with_context(|| format!("project path does not exist: {}", args.project.display()))?;
                let params = DeployParams {
                    rpc_url: args.rpc_url,
                    private_key: args.private_key,
                    callback: args.callback,
                    value: args.value,
                    contract_path: contract_path.to_string(),
                    project_dir,
                };
                let output = Runner::new(params).deploy()?;
                println!("{output}");
                Ok(())
            }
        },
    }
}
```

### Cargo.toml diff (the only change)
```toml
# Before:
clap = { version = "4.5", features = ["derive"] }

# After:
clap = { version = "4.5", features = ["derive", "env"] }
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `structopt` derive crate | clap 4.x `#[derive(Parser)]` | 2021 (clap 3.0) | structopt archived; clap 4.x derive is the maintained path |
| `std::env::var()` for env fallbacks | `#[arg(env = "VAR")]` with clap `env` feature | clap 3+ | Precedence (flag > env) handled automatically |
| `process::exit()` in main | `fn main() -> anyhow::Result<()>` or `run()` split | anyhow 1.0 | Either pattern works; `run()` split is preferred for testability |

## Open Questions

1. **`parse_value` float parsing edge case**
   - What we know: `num_str.parse::<f64>().is_ok()` accepts "0.0react", "1e3ether" — these are mathematically valid but unusual
   - What's unclear: whether Foundry accepts scientific notation in `--value`
   - Recommendation: Accept any `f64`-parseable prefix; Foundry will reject invalid values with its own error, which is still actionable

2. **`ETH_PRIVATE_KEY` stripping from subprocess env**
   - What we know: `primary.rs` only `env_remove`s `ETH_RPC_URL`; `--private-key` explicit flag overrides env
   - What's unclear: whether some Foundry version ignores explicit `--private-key` and uses `ETH_PRIVATE_KEY` env instead
   - Recommendation: Do not change `primary.rs` or `fallback.rs` in Phase 3; if this proves to be a bug, it is a Phase 2 fix

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Rust built-in (`cargo test`) |
| Config file | none — `cargo test` discovers tests in `#[cfg(test)]` modules |
| Quick run command | `cargo test --manifest-path d2p/Cargo.toml` |
| Full suite command | `cargo test --manifest-path d2p/Cargo.toml` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CMD-01 | `d2p ts reactive uniswap-v3` routes to correct handler | unit | `cargo test -p d2p test_cli_routing` | Wave 0 |
| CMD-02 | `ETH_RPC_URL` env var sets rpc_url when flag absent | unit | `cargo test -p d2p test_env_rpc_url` | Wave 0 |
| CMD-03 | `ETH_PRIVATE_KEY` env var sets private_key when flag absent | unit | `cargo test -p d2p test_env_private_key` | Wave 0 |
| CMD-04 | Missing `--callback` with no env causes error | unit | `cargo test -p d2p test_callback_required` | Wave 0 |
| CMD-05 | "10react" parses OK; "noreact" fails; "0.5ether" parses OK | unit | `cargo test -p d2p test_parse_value` | Wave 0 |
| CMD-06 | No `--legacy` flag exposed in help text | unit | `cargo test -p d2p test_no_legacy_flag` | Wave 0 |
| CMD-07 | `--help` text includes protocol name and example | unit | `cargo test -p d2p test_help_contains_example` | Wave 0 |
| CMD-08 | `--version` output matches Cargo.toml version | unit | `cargo test -p d2p test_version` | Wave 0 |
| CMD-09 | Non-existent `--project` path causes actionable error | unit | `cargo test -p d2p test_bad_project_path` | Wave 0 |
| OUT-02 | Stderr contains command attempted and error on failure | unit | `cargo test -p d2p test_stderr_on_failure` | Wave 0 |
| OUT-03 | exit code 0 on success, 1 on failure | integration | `cargo test -p d2p test_exit_codes` (binary invocation) | Wave 0 |

**Note on clap derive testing:** clap structs are tested by constructing `Cli::try_parse_from(vec!["d2p", ...])` — no binary invocation needed for most tests. This keeps tests fast and hermetic.

### Sampling Rate
- **Per task commit:** `cargo test --manifest-path d2p/Cargo.toml`
- **Per wave merge:** `cargo test --manifest-path d2p/Cargo.toml`
- **Phase gate:** Full suite green before verification

### Wave 0 Gaps
- [ ] `d2p/src/cli.rs` — the file does not exist yet; all tests in this file require it
- [ ] `d2p/src/cli.rs` test module — `parse_value` unit tests, `Cli::try_parse_from` routing tests
- [ ] `d2p/src/main.rs` — currently a stub (`Ok(())`); needs full implementation before integration tests

*(No new test infrastructure needed — `cargo test` already works for the crate)*

## Sources

### Primary (HIGH confidence)
- clap docs.rs derive tutorial (https://docs.rs/clap/latest/clap/_derive/_tutorial/index.html) — nested subcommands, `Parser`/`Args`/`Subcommand` derive, `env` attribute syntax
- clap Cargo.toml features section (read from `/home/jmsbpp/.cargo/registry/src/.../clap-4.5.60/Cargo.toml`) — confirmed `env` is a separate feature, NOT included in `default` or `derive`
- `cargo tree` output from d2p crate — confirmed clap resolves to 4.6.0, all current deps
- `d2p/src/deploy/mod.rs` (read) — `DeployParams` struct field names confirmed
- `d2p/src/deploy/primary.rs` (read) — contract_path format confirmed as `src/fee-concentration-index-v2/protocols/uniswap-v3/UniswapV3Reactive.sol:UniswapV3Reactive`
- `d2p/src/deploy/fallback.rs` (read) — contract name extraction from `contract_path` via `split(':').last()` confirmed
- `tmp/edge-rs/bin/edgec/src/cli.rs` (read) — in-repo reference for `#[arg(env = "EDGE_STD_PATH")]` pattern

### Secondary (MEDIUM confidence)
- Rust CLI Book exit codes chapter (https://rust-cli.github.io/book/in-depth/exit-code.html) — `std::process::exit(1)` pattern verified against anyhow docs

### Tertiary (LOW confidence)
- Foundry `--value` unit format acceptance for "react" denomination — unverified against live Foundry docs; assumed based on existing usage in test fixtures (`"10react"` in `test_params()`)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all deps already in Cargo.toml; only feature flag addition needed; verified via cargo tree
- Architecture: HIGH — all patterns are direct clap derive idioms verified against in-repo reference
- Pitfalls: HIGH — clap `env` feature gap confirmed by reading clap's own Cargo.toml features table directly
- Value parsing: MEDIUM — parse_value design is straightforward; Foundry's acceptance of "react" unit is LOW confidence (assumed from existing test fixtures)

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (clap 4.x is stable; no breaking changes expected)
