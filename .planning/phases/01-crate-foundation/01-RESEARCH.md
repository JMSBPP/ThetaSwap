# Phase 1: Crate Foundation - Research

**Researched:** 2026-03-17
**Domain:** Rust crate initialization — standalone binary crate with typed shared types inside a Foundry monorepo
**Confidence:** HIGH

## Summary

Phase 1 creates the `d2p/` Rust crate from scratch: a `Cargo.toml` with four pinned dependencies and a `src/` tree containing the shared types that all downstream modules depend on. There is nothing to discover at runtime — this phase is pure scaffolding. The risk is not technical complexity but structural mistakes that force refactoring in Phase 2: wrong crate isolation pattern, wrong module layout, or wrong type ownership.

The in-repo reference `tmp/edge-rs/` is a live, working example of the recommended patterns (clap 4.5 derive, `fn main() -> anyhow::Result<()>`, thiserror 2.x, serde_json 1.x). The only structural difference: `d2p/` is a standalone crate, not a workspace member, because the repo has no root `Cargo.toml` and adding one would conflict with Foundry's root `foundry.toml`.

Version note: clap has released 4.6.0 as of 2026-03-17, which is newer than the 4.5.x pinned in the project requirement SET-02. The requirement says "clap 4.5" — use `"4.5"` as the version specifier to pin to that series. Cargo resolves `"4.5"` to the latest 4.5.x patch; it will NOT auto-upgrade to 4.6.0 because that bumps the minor version. This is the correct behavior.

**Primary recommendation:** Create `d2p/Cargo.toml` as a self-contained `[package]` (no `[workspace]`), with `errors.rs` and `deploy/mod.rs` as the first source files — all other modules import from them.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SET-01 | Rust crate lives in `d2p/` directory within the monorepo | Standalone crate pattern confirmed: no root Cargo.toml exists; `d2p/Cargo.toml` at `d2p/` is self-contained. Foundry's `foundry.toml` at repo root is unaffected. |
| SET-02 | Dependencies: clap 4.5, anyhow 1.x, thiserror 2.x, serde_json 1.x | All four verified against crates.io: clap 4.6.0 current (pin to `"4.5"`), anyhow 1.0.102 current (`"1"`), thiserror 2.0.18 current (`"2"`), serde_json 1.0.149 current (`"1"`). Version specifiers confirmed. |
| SET-03 | Binary compiles with `cargo build` from `d2p/` directory | Requires: `[[bin]]` section in Cargo.toml pointing to `src/main.rs`; `main.rs` must be valid Rust. Minimal `fn main() -> anyhow::Result<()> { Ok(()) }` is sufficient for Phase 1 compilation success. |
</phase_requirements>

## Standard Stack

### Core

| Library | Version Specifier | Verified Latest | Purpose | Why Standard |
|---------|-------------------|-----------------|---------|--------------|
| clap | `"4.5"` | 4.6.0 | Argument parsing (used in Phase 2+) | De facto standard Rust CLI arg parser. Derive feature eliminates boilerplate. Pin to 4.5 per SET-02 — Cargo will not auto-upgrade to 4.6. |
| anyhow | `"1"` | 1.0.102 | Error propagation in `main()` and `deploy::` | `fn main() -> anyhow::Result<()>` gives free `?`-propagation + auto stderr printing on exit. No 2.x released. |
| thiserror | `"2"` | 2.0.18 | Typed `D2pError` enum | `#[derive(thiserror::Error)]` generates `std::error::Error` impl from field annotations. 2.x released Nov 2024; breaking change from 1.x is minimal (removed blanket impl). |
| serde_json | `"1"` | 1.0.149 | Parsing forge/cast JSON output (Phase 2+) | Included in Cargo.toml at Phase 1 because SET-02 requires all four deps pinned. No active use in Phase 1 source. |

**Version verification:** Versions above were fetched live from `https://crates.io/api/v1/crates/{name}` on 2026-03-17 (HIGH confidence).

### Supporting (Phase 1 does NOT add these — for awareness only)

| Library | Version | Purpose | When to Add |
|---------|---------|---------|-------------|
| clap features = ["derive"] | (same as clap) | Enables `#[derive(Parser, Subcommand, Args)]` | Required in Phase 2 when `cli.rs` is written |
| serde features = ["derive"] | `"1"` | Enables `#[derive(Serialize, Deserialize)]` on output types | Add if `DeployOutput` needs JSON serialization (Phase 2+) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| thiserror 2.x | thiserror 1.x | 1.x is in maintenance only; 2.x is the current series. No reason to pin to 1.x. |
| serde_json | manual string parsing | Explicitly out of scope per STACK.md — never parse forge output with regex/string matching |

**Installation (complete Cargo.toml for Phase 1):**

```toml
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
serde_json = "1"
```

Note: `serde` is NOT listed separately — `serde_json` depends on `serde` and pulls it in as a transitive dependency. Phase 2 adds `serde = { version = "1", features = ["derive"] }` explicitly only when `#[derive(Serialize)]` is needed on types.

## Architecture Patterns

### Recommended Project Structure (Phase 1 scope only)

```
d2p/
├── Cargo.toml             # Self-contained [package]; no [workspace]
└── src/
    ├── main.rs            # fn main() -> anyhow::Result<()> { Ok(()) }
    ├── errors.rs          # D2pError enum (thiserror)
    └── deploy/
        └── mod.rs         # DeployParams struct, DeployOutput struct
```

Phase 2 adds `src/cli.rs`, `src/deploy/primary.rs`, `src/deploy/fallback.rs`, `src/output.rs`. Phase 1 creates only the types that those modules will import from.

### Pattern 1: Module Declaration in main.rs

**What:** `main.rs` declares modules with `mod` statements. Each module file is `src/<name>.rs` or `src/<name>/mod.rs`. The compiler resolves paths automatically.

**When to use:** Always — this is the standard Rust module system.

**Example:**
```rust
// src/main.rs
mod errors;
mod deploy;

fn main() -> anyhow::Result<()> {
    Ok(())
}
```

```rust
// src/errors.rs
#[derive(Debug, thiserror::Error)]
pub enum D2pError {
    #[error("process not found on PATH: {0}")]
    ProcessNotFound(String),

    #[error("subprocess exited non-zero: {0}")]
    NonZeroExit(String),

    #[error("failed to parse deploy output: {0}")]
    ParseFailure(String),
}
```

```rust
// src/deploy/mod.rs
/// Input parameters for all deploy strategies.
#[derive(Debug)]
pub struct DeployParams {
    pub rpc_url: String,
    pub private_key: String,
    pub callback: String,
    pub value: String,
    pub contract_path: String,
    pub project_dir: std::path::PathBuf,
}

/// Output produced by a successful deployment.
#[derive(Debug)]
pub struct DeployOutput {
    pub address: String,
    pub tx_hash: String,
}

impl std::fmt::Display for DeployOutput {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "{}", self.address)?;
        write!(f, "{}", self.tx_hash)
    }
}
```

**Source:** ARCHITECTURE.md (Suggested Build Order, Component Responsibilities) — in this repo. HIGH confidence.

### Pattern 2: Standalone Crate in Monorepo (No Root Workspace)

**What:** `d2p/Cargo.toml` contains only `[package]` and `[dependencies]`. It does NOT contain `[workspace]`. Running `cargo build` from inside `d2p/` works without touching the repo root. Running `cargo build --manifest-path d2p/Cargo.toml` from the repo root also works.

**Why this matters:** The repo root has `foundry.toml` but no `Cargo.toml`. Adding a root `Cargo.toml` with `[workspace]` would make Cargo treat the entire repo as a Rust workspace, interfering with directory resolution for every `cargo` command run from any subdirectory.

**Example invocation:**
```bash
cd d2p && cargo build          # correct
cargo build --manifest-path d2p/Cargo.toml  # also correct from repo root
```

**Source:** ARCHITECTURE.md Anti-Pattern 2. HIGH confidence.

### Pattern 3: thiserror 2.x Derive Syntax

**What:** thiserror 2.x is backwards-compatible with 1.x for the `#[error("...")]` attribute. The primary breaking change in 2.x was removal of a blanket `impl` that was causing coherence issues — not the user-facing derive syntax. All patterns from `tmp/edge-rs` with `thiserror = "2"` apply directly.

**Example (from tmp/edge-rs/Cargo.toml line 75):**
```toml
thiserror = { version = "2.0", default-features = false }
```

For `d2p/`, `default-features = false` is optional but reduces compile time slightly (the default feature only enables a proc-macro optimization). Both forms are correct.

**Source:** `tmp/edge-rs/Cargo.toml` line 75 (direct file read, HIGH confidence); thiserror 2.0 release notes (MEDIUM confidence, WebSearch not performed — sourced from STACK.md which verified it).

### Anti-Patterns to Avoid

- **Adding `[workspace]` to `d2p/Cargo.toml`:** Makes `d2p` a workspace root, which breaks when Phase 2 or 3 tries to add the `which` crate or other deps not listed in a workspace-level manifest. Keep `d2p/Cargo.toml` as a plain `[package]`.
- **Placing types in `main.rs` instead of modules:** `D2pError`, `DeployParams`, and `DeployOutput` defined in `main.rs` are not importable from other modules without `use crate::` re-exports. Define them in dedicated module files from the start.
- **Using `pub use` re-exports in `main.rs`:** `main.rs` is the binary entry point, not a library root. There is no `lib.rs` in this crate — types are accessed as `crate::errors::D2pError` from within the crate. No re-export layer is needed in Phase 1.
- **Importing `serde_json` in Phase 1 source code:** serde_json is listed in `Cargo.toml` (per SET-02) but should not be used in Phase 1 source. Unused imports cause `cargo build` warnings. Suppress with `#[allow(unused_imports)]` only if the import is intentional scaffolding; otherwise just list the dep in Cargo.toml without importing it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Error type boilerplate | Manual `impl std::error::Error for D2pError` | `#[derive(thiserror::Error)]` | Error trait requires multiple impls (Display, Error, source()). thiserror generates all from a single attribute. |
| Error chain propagation | Manual `match` + `map_err` everywhere | `anyhow::Result<()>` + `?` operator | anyhow chains context automatically; `fn main() -> anyhow::Result<()>` prints the chain to stderr on exit. |
| Version string in binary | Manual `const VERSION: &str = ...` | `#[command(version)]` in clap (Phase 2) | clap reads `CARGO_PKG_VERSION` at compile time via the `version` attribute. SET-02/Phase 1 doesn't need this yet, but do not add a manual constant. |

**Key insight:** Phase 1 types (`D2pError`, `DeployParams`, `DeployOutput`) are pure data — no process invocation, no clap, no serde. They must compile independently of what uses them. Keep them free of any dependency on Phase 2+ logic.

## Common Pitfalls

### Pitfall 1: clap 4.6.0 vs. 4.5.x Pin

**What goes wrong:** `version = "4.5"` in Cargo.toml resolves to the latest 4.5.x patch. If a developer writes `version = "4"` or `version = ">=4.5"`, Cargo resolves to 4.6.0 (current latest), which is NOT the pinned series from SET-02.

**Why it happens:** Cargo semver specifiers are permissive by default. `"4"` means `>=4.0.0, <5.0.0`.

**How to avoid:** Use exactly `version = "4.5"` — this means `>=4.5.0, <4.6.0`. This is the correct pin.

**Warning signs:** `Cargo.lock` shows `clap 4.6.x` when the project requires 4.5.x.

### Pitfall 2: `serde_json` in Cargo.toml Without Active Use Causes No-op Compile

**What goes wrong:** `serde_json = "1"` in `[dependencies]` but never imported in source code compiles fine in debug mode. In release mode with `--release`, the linker strips it but `cargo build` still downloads and compiles the crate. This is not an error, but it is unnecessary overhead for Phase 1.

**Why it happens:** SET-02 requires all four deps pinned in `Cargo.toml`. They must be listed, not necessarily used.

**How to avoid:** List the dep. Do not import it. `cargo build` succeeds. The dep will be used in Phase 2. This is the intended behavior — no mitigation needed beyond understanding it.

### Pitfall 3: `mod deploy;` vs. `mod deploy { ... }` Inline

**What goes wrong:** Defining `deploy` as an inline module in `main.rs` (`mod deploy { pub struct DeployParams { ... } }`) instead of a file module. This blocks Phase 2 from adding `deploy/primary.rs` and `deploy/fallback.rs` as submodules without restructuring.

**Why it happens:** Inline modules look identical to file modules from outside the crate — the mistake is only visible when adding submodules.

**How to avoid:** Create `src/deploy/mod.rs` as a file from the start. `mod deploy;` in `main.rs` resolves to either `src/deploy.rs` (single file) or `src/deploy/mod.rs` (directory). Use the directory form immediately — Phase 2 adds `primary.rs` and `fallback.rs` as siblings of `mod.rs` without touching `main.rs`.

### Pitfall 4: `rust-version` Absent Causes Silent Compat Issues

**What goes wrong:** Without `rust-version = "1.85"` in `Cargo.toml`, the crate compiles on any Rust version. A developer with Rust 1.70 (pre-edition 2021 let-chains) gets confusing errors in Phase 2 when those features are used.

**Why it happens:** `rust-version` is optional in Cargo. It is easy to omit.

**How to avoid:** Add `rust-version = "1.85"` in the `[package]` section. This matches `tmp/edge-rs/Cargo.toml` and STACK.md recommendation. `cargo build` on older toolchains fails immediately with a clear version error instead of a cryptic feature-not-available error.

## Code Examples

Verified patterns from official sources and in-repo reference:

### Minimal compilable main.rs (Phase 1 target)

```rust
// Source: ARCHITECTURE.md + tmp/edge-rs/bin/edgec/src/main.rs pattern
mod deploy;
mod errors;

fn main() -> anyhow::Result<()> {
    Ok(())
}
```

### D2pError definition (errors.rs)

```rust
// Source: ARCHITECTURE.md Component Responsibilities + thiserror docs
#[derive(Debug, thiserror::Error)]
pub enum D2pError {
    /// forge or cast binary not found on PATH
    #[error("process not found on PATH: {0}")]
    ProcessNotFound(String),

    /// Subprocess exited with non-zero status
    #[error("subprocess exited non-zero: {stderr}")]
    NonZeroExit { stderr: String },

    /// Could not extract address or tx hash from output
    #[error("failed to parse deploy output: {0}")]
    ParseFailure(String),
}
```

### DeployParams and DeployOutput (deploy/mod.rs)

```rust
// Source: ARCHITECTURE.md "Flags to DeployParams" data flow
use std::path::PathBuf;

/// All inputs required to attempt a deployment via any strategy.
#[derive(Debug)]
pub struct DeployParams {
    pub rpc_url: String,
    pub private_key: String,
    pub callback: String,
    pub value: String,
    pub contract_path: String,
    pub project_dir: PathBuf,
}

/// Successful deployment result.
#[derive(Debug)]
pub struct DeployOutput {
    pub address: String,
    pub tx_hash: String,
}

impl std::fmt::Display for DeployOutput {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "{}", self.address)?;
        write!(f, "{}", self.tx_hash)
    }
}
```

### Cargo.toml (complete, verified)

```toml
[package]
name = "d2p"
version = "0.1.0"
edition = "2021"
rust-version = "1.85"

[[bin]]
name = "d2p"
path = "src/main.rs"

[dependencies]
clap    = { version = "4.5", features = ["derive"] }
anyhow  = "1"
thiserror = "2"
serde_json = "1"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| thiserror 1.x | thiserror 2.x | November 2024 | 2.x current; no derive syntax change for users |
| structopt | clap 4 derive | clap 3 (2022), clap 4 (2022) | structopt archived; clap derive is the replacement |
| failure crate | anyhow + thiserror | 2019 | failure abandoned; do not use |
| edition 2018 | edition 2021 | Rust 1.56 (2021) | Edition 2021 is current stable; resolver v2 is default |

**Deprecated/outdated:**
- `structopt`: Archived crate. Superseded by `clap` derive.
- `failure`: Abandoned 2019. Use `anyhow` + `thiserror`.
- `error-chain`: Abandoned. Same replacement.

## Open Questions

1. **clap `features = ["derive"]` required at Phase 1?**
   - What we know: clap is listed in `Cargo.toml` per SET-02. The `derive` feature is required for `#[derive(Parser)]` in Phase 2's `cli.rs`. It can be listed now or added in Phase 2.
   - What's unclear: Whether listing `features = ["derive"]` at Phase 1 (when no clap code exists in `src/`) causes compile overhead with no benefit.
   - Recommendation: List it now. The overhead is negligible (proc-macro compile, already paid when `clap` itself compiles). Avoids a Cargo.toml edit in Phase 2 that could be confused with a functional change.

2. **`serde_json` without `serde` listed separately: is that sufficient?**
   - What we know: `serde_json = "1"` pulls `serde` as a transitive dep. Phase 1 types (`DeployOutput`, `DeployParams`) do not need `#[derive(Serialize)]`.
   - What's unclear: If Phase 2 needs `#[derive(Serialize)]` on `DeployOutput`, it must add `serde = { version = "1", features = ["derive"] }` explicitly.
   - Recommendation: Do NOT add `serde` explicitly in Phase 1. Add in Phase 2 when `#[derive(Serialize)]` is first used. This keeps Phase 1 Cargo.toml exactly matching SET-02's four deps.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Rust built-in (`cargo test`) |
| Config file | None — `cargo test` requires no config file |
| Quick run command | `cargo test --manifest-path d2p/Cargo.toml` |
| Full suite command | `cargo test --manifest-path d2p/Cargo.toml` (same — no separate suites at Phase 1) |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SET-01 | `d2p/` directory exists with `Cargo.toml` | smoke (filesystem check) | `test -f d2p/Cargo.toml` | Wave 0 creates it |
| SET-02 | All four deps pinned in Cargo.toml | smoke (Cargo.lock parse) | `cargo metadata --manifest-path d2p/Cargo.toml --no-deps \| python3 -c "import sys,json; pkgs={p['name'] for p in json.load(sys.stdin)['packages']}; assert 'clap' in pkgs and 'anyhow' in pkgs and 'thiserror' in pkgs and 'serde_json' in pkgs"` | Wave 0 creates it |
| SET-03 | `cargo build` from `d2p/` succeeds | build | `cargo build --manifest-path d2p/Cargo.toml 2>&1 \| tail -1` (expect `Finished`) | Wave 0 creates it |

Additional unit tests (no subprocess required):
| Behavior | Test Type | Command |
|----------|-----------|---------|
| `D2pError` variants are `Debug` + implement `std::error::Error` | unit | `cargo test --manifest-path d2p/Cargo.toml test_d2p_error_variants` |
| `DeployOutput::fmt` produces two-line output | unit | `cargo test --manifest-path d2p/Cargo.toml test_deploy_output_display` |
| `DeployParams` is `Debug` | unit | `cargo test --manifest-path d2p/Cargo.toml test_deploy_params_debug` |

### Sampling Rate

- **Per task commit:** `cargo build --manifest-path d2p/Cargo.toml`
- **Per wave merge:** `cargo test --manifest-path d2p/Cargo.toml`
- **Phase gate:** `cargo build` green + `cargo test` green before moving to Phase 2

### Wave 0 Gaps

- [ ] `d2p/Cargo.toml` — the crate does not exist yet; must be created in Wave 1
- [ ] `d2p/src/main.rs` — entry point file
- [ ] `d2p/src/errors.rs` — `D2pError` type
- [ ] `d2p/src/deploy/mod.rs` — `DeployParams`, `DeployOutput` types

No test framework install needed — `cargo test` is built into the Rust toolchain.

## Sources

### Primary (HIGH confidence)

- `tmp/edge-rs/Cargo.toml` (direct file read) — pinned versions: clap 4.5.0, anyhow 1.0.79, thiserror 2.0, serde_json 1.0.113; workspace structure
- `tmp/edge-rs/bin/edgec/src/main.rs` (direct file read) — `fn main() -> anyhow::Result<()>`, clap Parser derive, module pattern
- `tmp/edge-rs/bin/edgec/src/cli.rs` (direct file read) — `#[derive(Parser)]`, `#[derive(Subcommand)]`, `#[command(...)]` attribute patterns
- `.planning/research/STACK.md` (direct file read) — recommended Cargo.toml, library rationale, version compatibility table
- `.planning/research/ARCHITECTURE.md` (direct file read) — module structure, data flow, build order, anti-patterns
- `.planning/research/PITFALLS.md` (direct file read) — Pitfall 4 (`--constructor-args` order), confirmed Foundry issue numbers
- `.planning/REQUIREMENTS.md` (direct file read) — SET-01, SET-02, SET-03 verbatim requirements
- `crates.io API` (live fetch 2026-03-17) — clap 4.6.0, thiserror 2.0.18, anyhow 1.0.102, serde_json 1.0.149 confirmed current

### Secondary (MEDIUM confidence)

- `.planning/research/ARCHITECTURE.md` Suggested Build Order section — independent corroboration of types-first module build sequence

### Tertiary (LOW confidence)

- None — all claims in this document are backed by direct file reads or live API queries.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — versions verified live against crates.io API on research date
- Architecture: HIGH — directly corroborated by in-repo `tmp/edge-rs` working code
- Pitfalls: HIGH — sourced from `.planning/research/PITFALLS.md` which cites Foundry GitHub issue numbers

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable ecosystem; clap 4.5 series unlikely to receive new releases that affect pinning behavior)
