# Stack Research

**Domain:** Rust CLI wrapping Foundry (forge/cast) for smart contract deployment
**Researched:** 2026-03-17
**Confidence:** HIGH

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Rust (edition 2021) | stable (1.85+) | Language | User-specified. Edition 2021 is the current stable edition; resolver v2 is default. Already used in `tmp/edge-rs` within this repo. |
| clap | 4.5.x | Argument parsing and subcommand routing | De-facto standard for Rust CLIs. `#[derive(Parser, Subcommand)]` gives zero-boilerplate flag definitions. clap 4.x has been stable since 2022; 4.5.x is the current active series. The `derive` feature produces exactly the `d2p ts reactive uniswap-v3 --rpc-url --private-key --callback --value` shape with no manual builder code. |
| anyhow | 1.0.x | Application-layer error propagation | `fn main() -> anyhow::Result<()>` gives free `?`-propagation throughout main with automatic stderr error printing on exit. Perfect for a CLI where errors are user-facing strings, not typed variants callers match on. Still on 1.x (no 2.0 released). |
| thiserror | 2.0.x | Typed error definitions for domain errors | Needed only if subprocess errors need distinct variants (e.g., `ForgeCreateFailed`, `CastSendFailed`). thiserror 2.0 released November 2024. Combine with anyhow: thiserror for the domain error enum, anyhow wraps it at the boundary. |
| std::process::Command | stdlib | Spawning forge / cast subprocesses | **Do not use tokio::process::Command.** d2p runs one command at a time sequentially (forge, then cast as fallback). There is no concurrency benefit. Std Command is simpler, has no runtime dependency, and captures stdout/stderr cleanly with `.output()`. This is exactly how `tmp/edge-rs` driver code invokes foundry-compilers internally. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| serde / serde_json | 1.0.x | Parsing forge/cast JSON output | `forge create --json` and `cast send --json` emit structured JSON. Parse with serde_json to extract `deployedTo` and `transactionHash` fields reliably rather than grep-ing stdout. Use when structured output is available (it is). |
| which | 7.x | PATH lookup for forge and cast | Verify `forge` and `cast` are on PATH before attempting to run them. Provides a clear error "forge not found on PATH, install Foundry" rather than an opaque `No such file or directory`. Optional but improves UX significantly. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| cargo (workspace) | Build and dependency management | d2p lives under a `d2p/` directory inside the existing repo. Use a standalone `Cargo.toml` (no workspace root required at repo level since there is no repo-level Cargo.toml). |
| clippy | Linting | `cargo clippy -- -D warnings` in CI. The edge-rs workspace in this repo shows a comprehensive clippy config; copy the relevant lints. |
| rustfmt | Formatting | Default settings sufficient for a small CLI. |

## Installation

```toml
# d2p/Cargo.toml

[package]
name = "d2p"
version = "0.1.0"
edition = "2021"
rust-version = "1.85"

[[bin]]
name = "d2p"
path = "src/main.rs"

[dependencies]
clap = { version = "4.5", features = ["derive"] }
anyhow = "1"
thiserror = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
which = "7"
```

```bash
# Build
cargo build --release --manifest-path d2p/Cargo.toml

# Run
./d2p/target/release/d2p ts reactive uniswap-v3 \
  --rpc-url https://rpc.sepolia.org \
  --private-key 0xdeadbeef \
  --callback 0xc9f36411...
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| std::process::Command | tokio::process::Command | Only if the CLI needs concurrent subprocess execution (e.g., parallel deploys). d2p is strictly sequential: forge, then cast fallback. Tokio adds ~4MB binary weight and async complexity for zero benefit here. |
| anyhow | eyre | eyre provides color-spantrace on panics. Useful for library-level diagnostic tools. d2p is a thin wrapper; anyhow's simpler API is sufficient. |
| clap derive | clap builder | Use builder if you need runtime-dynamic subcommands or highly custom help formatting. For d2p's static command tree, derive is strictly less code. |
| serde_json | regex/grep on stdout | Regex on forge output breaks whenever Foundry updates its stdout format. JSON output (`--json` flag) is stable and explicitly versioned. Never parse forge output with string matching. |
| which crate | rely on OS error | which gives a proactive, human-readable error before attempting spawn. Improves DX at minimal cost (< 500 LOC dependency). |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| tokio (as #[tokio::main]) | d2p has no async I/O. No network calls, no concurrent processes. Adding an async runtime for a synchronous sequential CLI adds ~4MB binary size, complicates error handling, and provides nothing. | std::process::Command with blocking .output() |
| indicatif / spinners | d2p is pipe-friendly. Progress spinners write to tty and break pipe consumers. forge/cast already emit their own progress. | Nothing — let forge/cast own their stderr output |
| reqwest / ethers-rs / alloy | d2p shells out to forge/cast; it must not reimplement RPC communication in-process. Adding alloy pulls in hundreds of transitive dependencies and defeats the purpose of the tool. | std::process::Command shelling to cast |
| structopt | Superseded by clap 4 derive. structopt is archived and unmaintained. | clap 4 with features = ["derive"] |
| failure (crate) | Abandoned in 2019. | anyhow + thiserror |
| tracing + tracing-subscriber | d2p is a thin deployment wrapper, not a server. No structured logging needed. `eprintln!` to stderr is sufficient and keeps the binary lean. | eprintln! for diagnostic output to stderr |

## Stack Patterns by Variant

**For the primary deploy path (forge create):**
- Run `std::process::Command::new("forge").args([...]).output()`
- On exit code 0: parse `--json` stdout with `serde_json`, extract `deployedTo` + `transactionHash`, print to stdout
- On non-zero: capture stderr, propagate as `anyhow::bail!("forge create failed: {stderr}")`

**For the fallback path (cast send --create):**
- Triggered when forge create exits non-zero (RPC ignore bug)
- Run `std::process::Command::new("cast").args(["send", "--create", ...]).output()`
- Parse `--json` output for `contractAddress` + `transactionHash`
- On failure: `anyhow::bail!` with aggregated errors from both attempts

**For arg parsing (clap subcommand shape):**
```
d2p ts reactive <protocol>
     ^  ^        ^
     |  |        Protocol variant (uniswap-v3, future: uniswap-v4)
     |  Subcommand
     Top-level subcommand group
```
Map to: `Cli -> Commands::Ts -> TsCommands::Reactive { protocol, rpc_url, private_key, callback, value }`

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| clap 4.5.x | Rust 1.74+ | Minimum Rust version per clap 4.5 release notes |
| anyhow 1.x | Rust 1.39+ | No compatibility concerns |
| thiserror 2.x | Rust 1.61+ | 2.0 requires proc-macro2 1.0.60+; resolved automatically |
| serde_json 1.x | serde 1.x | Must use same serde major version; both at 1.x |
| which 7.x | Rust 1.70+ | 7.x released 2024; uses std::sync::OnceLock |

All packages compatible with Rust 1.85 (the minimum set in `tmp/edge-rs` in this repo).

## In-Repo Reference

`tmp/edge-rs/` is a working Rust CLI in this repository that demonstrates the exact recommended pattern:
- `clap 4.5` with `#[derive(Parser, Subcommand)]` — `tmp/edge-rs/bin/edgec/src/cli.rs`
- `fn main() -> anyhow::Result<()>` — `tmp/edge-rs/bin/edgec/src/main.rs`
- `eprintln!` to stderr, `println!` to stdout — `tmp/edge-rs/bin/edgec/src/cli.rs:204`
- `thiserror 2.0`, `serde_json 1.0` — `tmp/edge-rs/Cargo.toml`
- Standalone binary under `bin/` directory, workspace-linked — `tmp/edge-rs/Cargo.toml:2`

The only difference for d2p: no tokio dependency (edgec uses it only for its LSP subcommand; d2p has no async subcommands).

## Sources

- WebSearch: clap crates.io — 4.5.x confirmed as current active series (MEDIUM confidence; crates.io not directly fetched)
- WebSearch: tokio 1.50 current stable, LTS 1.47.x until Sept 2026 (MEDIUM confidence)
- WebSearch: thiserror 2.0.18, released 2024-11-06 (HIGH confidence — release date explicitly in search results)
- WebSearch: anyhow remains at 1.x, no 2.0 release (HIGH confidence — confirmed by thiserror dev-deps referencing `anyhow ^1.0.73`)
- WebSearch: std vs tokio process::Command — sync preferred when no concurrency needed (HIGH confidence — official tokio docs cited)
- In-repo evidence: `tmp/edge-rs/Cargo.toml` — pinned versions of clap 4.5.0, anyhow 1.0.79, thiserror 2.0, serde_json 1.0.113 (HIGH confidence — direct file read)
- WebSearch: forge `--json` flag and cast `--json` flag for structured output (MEDIUM confidence — Foundry docs not directly fetched)

---
*Stack research for: Rust CLI (d2p) wrapping Foundry forge/cast for smart contract deployment*
*Researched: 2026-03-17*
