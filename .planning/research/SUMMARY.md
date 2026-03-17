# Project Research Summary

**Project:** d2p — Rust CLI wrapping Foundry for reactive contract deployment
**Domain:** Rust CLI process-wrapper for smart contract deployment (Foundry toolchain)
**Researched:** 2026-03-17
**Confidence:** HIGH

## Executive Summary

`d2p` is a thin Rust CLI that solves a specific, well-documented problem: `forge create` silently ignores `--rpc-url` on Reactive Network (Lasna), causing deployments to land on the wrong chain without error. The tool wraps both `forge create` (primary) and `cast send --create` (fallback) behind a single command — `d2p ts reactive uniswap-v3` — so deployment scripts never need to implement that fallback logic themselves. The scope is intentionally narrow: one command, one protocol, pipe-friendly output.

The recommended implementation is a 6-module Rust crate (clap + anyhow + serde_json, no tokio) with a strict separation between CLI arg parsing and subprocess invocation. The key architectural insight is that `cli.rs` converts parsed args into a `DeployParams` struct before touching `deploy::`, keeping business logic testable without spawning processes. The try-primary/fallback runner pattern is the core differentiator; all other features are table stakes shared with `forge create` itself.

The dominant risks are not implementation complexity but Foundry reliability: `forge create` output format can change silently between releases, exit code 0 does not guarantee a live contract, and `--value` can be silently dropped from payable constructors. Each of these has a verified mitigation (prefix-matching rather than label-matching for output parsing, `cast receipt` status check post-deploy, explicit `--value` validation + post-deploy balance assertion). Implementing all three mitigations is non-negotiable for the correctness guarantee the tool's pipe-friendly contract requires.

## Key Findings

### Recommended Stack

The entire stack is synchronous and dependency-light. There is no async I/O, no network calls, no concurrent subprocess execution. Adding tokio would add ~4MB binary size for zero benefit. The existing `tmp/edge-rs/` workspace in this repo demonstrates the exact pattern: clap 4.5 derive, `fn main() -> anyhow::Result<()>`, thiserror 2.0, serde_json 1.0, eprintln! to stderr. The d2p crate is simpler than edge-rs (no tokio subcommand).

**Core technologies:**
- Rust 1.85, edition 2021: user-specified; no compatibility issues with any dependency
- clap 4.5 (derive feature): zero-boilerplate subcommand tree via `#[derive(Parser, Subcommand, Args)]`; handles `--help`, `--version`, env var fallbacks, and the nested `d2p ts reactive <protocol>` shape for free
- anyhow 1.x: `fn main() -> anyhow::Result<()>` gives free `?`-propagation and automatic stderr printing on exit; correct for application-layer errors
- thiserror 2.0: typed `D2pError` enum for domain errors inside `deploy::`; wrapped by anyhow at the boundary
- serde / serde_json 1.x: parse `forge create --json` and `cast send --json` output reliably; never grep stdout
- std::process::Command (stdlib): spawn forge/cast sequentially; `.output()` buffers stdout + stderr; no tokio needed
- which 7.x: PATH lookup at startup for actionable "install Foundry" error before any subprocess attempt

**What NOT to use:** tokio, reqwest, alloy, ethers-rs, indicatif, interactive TUI libraries, structopt, tracing-subscriber.

### Expected Features

The feature surface is deliberately minimal. The competitive advantage is the forge-to-cast automatic fallback, not feature breadth. Everything else is standard POSIX CLI hygiene.

**Must have (table stakes for v1):**
- `d2p ts reactive uniswap-v3` single-command deployment — the entire stated scope
- `--rpc-url`, `--private-key`, `--callback`, `--value` flags with `ETH_RPC_URL` / `ETH_PRIVATE_KEY` env var fallbacks
- `--legacy` baked in unconditionally for reactive subcommand — Lasna requires it; missing it = silent deployment failure
- Primary path: `forge create` with `--broadcast --legacy`
- Fallback path: `cast send --create` on `forge create` failure — core stated value of d2p
- Stdout: deployed address + tx hash on success, nothing else
- Stderr: error message on failure; exit 1
- Foundry PATH check at startup: `which forge && which cast`

**Should have (v1.x, add after validation):**
- `--json` output flag for downstream tooling (`{"address": "0x...", "tx": "0x..."}`)
- Payable value unit parsing (`0.01ether` → wei via cast conventions)

**Defer (v2+):**
- `d2p ts reactive uniswap-v4` — subcommand structure already supports it; add when V4 deployment is a milestone
- Additional `d2p ts` subcommands (non-reactive)

**Explicitly excluded (anti-features):** interactive TUI, deployment artifact registry, Etherscan verification, wallet/keystore management, dry-run/simulation, multi-contract orchestration, config file (TOML/YAML).

### Architecture Approach

The architecture is a 4-layer stack (CLI Entry → Command → Execution → Output/Error) with clean module boundaries. The critical design constraint is that `deploy::` modules must be testable without clap or a real forge binary — this forces `DeployParams` as the interface struct and means `main.rs` stays under 40 lines. The fallback runner is the most important module; it must log a warning to stderr when switching from forge to cast so the user knows which path succeeded.

**Major components:**
1. `cli.rs` — Cli struct, Commands/TsCommands/ReactiveArgs enums, Protocol enum; clap derive only; converts to DeployParams; no process invocation
2. `deploy/mod.rs` + `Runner` — DeployParams, DeployOutput, try-primary-then-fallback orchestration; the core differentiator lives here
3. `deploy/primary.rs` — `forge create` invocation, arg list construction, stdout parsing, returns `anyhow::Result<DeployOutput>`
4. `deploy/fallback.rs` — `cast send --create` invocation, same interface as primary; independent fallback strategy
5. `errors.rs` — `D2pError` (thiserror) for typed errors: process-not-found, non-zero exit, parse failure
6. `output.rs` — `DeployOutput` struct with `Display` impl for pipe-friendly address + hash printing

**Build order (dependency-driven):** errors.rs → output.rs → deploy/mod.rs (DeployParams) → deploy/primary.rs → deploy/fallback.rs → deploy/mod.rs (Runner) → cli.rs → main.rs → tests/integration.rs.

### Critical Pitfalls

1. **forge create silently ignores --rpc-url** — Remove `ETH_RPC_URL` from child process environment with `.env_remove("ETH_RPC_URL")` before spawning; verify chain ID post-deployment with `cast chain-id`. This is the foundational reason d2p exists; the fallback to `cast send --create` is the primary mitigation.

2. **Exit code 0 does not mean deployment succeeded** — After parsing tx hash, call `cast receipt <txhash> --field status` and assert `0x1`; only then print address to stdout. Both `forge create` and `cast send` can exit 0 with a reverted constructor.

3. **--value silently dropped from payable constructor** — Treat `--value` as required for UniswapV3Reactive; validate at CLI startup; verify `cast balance <address>` equals supplied value post-deploy. Zero-balance reactive contract fails silently at callback time, not at deploy time.

4. **--constructor-args position bug in forge create** — Always put `--constructor-args` last in the arg list; write a unit test asserting arg order as `Vec<OsString>` without spawning a process.

5. **Private key leaked via /proc/<pid>/cmdline and child environment** — Use `.env_clear()` on Command then set only PATH and HOME; mark clap field with `hide_env_values(true)`; never include key value in any log or error string.

## Implications for Roadmap

Based on combined research, the dependency graph from FEATURES.md and the build order from ARCHITECTURE.md converge on three natural phases. The tool is small enough that each phase can ship a testable artifact.

### Phase 1: Foundation — Types, Errors, and Deploy Interface

**Rationale:** All other modules depend on `D2pError`, `DeployOutput`, and `DeployParams`. These have no external dependencies and can be written and unit-tested before any subprocess invocation. Establishing them first prevents interface churn in later phases. The ARCHITECTURE.md build order explicitly identifies this as step 1-2.

**Delivers:** Compilable crate skeleton with typed error enum, deploy output struct, deploy params struct, and Cargo.toml with all dependencies pinned.

**Addresses:** No features yet — this is infrastructure only.

**Avoids:** Anti-pattern of single `main.rs` file; forces testable module boundaries from the start.

**Research flag:** No deeper research needed. Standard Rust patterns; in-repo `tmp/edge-rs/` is a direct reference.

### Phase 2: Core Deploy Logic — Primary and Fallback Paths

**Rationale:** `deploy/primary.rs` and `deploy/fallback.rs` are the core value of d2p. They must be implemented and tested before wiring up the CLI, because the fallback behavior is the primary differentiator and has the highest pitfall density. Implementing both paths before `cli.rs` means they can be tested via direct Rust function calls without argument parsing, making bugs easier to isolate.

**Delivers:** Working `Runner::deploy()` that tries `forge create` and falls back to `cast send --create`, parses output, verifies receipt status, and returns `DeployOutput` or a typed error.

**Addresses (features):** forge-to-cast automatic fallback (core differentiator), `--legacy` baked in, stdout address + tx hash / stderr errors, exit codes.

**Implements (architecture):** deploy/primary.rs, deploy/fallback.rs, Runner try-fallback pattern, captured output parsing, post-deploy verification step.

**Avoids (pitfalls):**
- Pitfall 1: env_remove("ETH_RPC_URL") in Command builder; chain ID verification
- Pitfall 2: cast receipt status check before returning DeployOutput
- Pitfall 3: --value forwarded to both code paths; balance assertion
- Pitfall 4: --constructor-args placed last; unit test asserting arg Vec order

**Research flag:** No deeper research needed. All patterns are well-documented; Foundry issues are cited in PITFALLS.md.

### Phase 3: CLI Wiring and End-to-End Integration

**Rationale:** Once the deploy logic is proven, `cli.rs` is purely mechanical: derive clap structs that match the documented `d2p ts reactive uniswap-v3 --rpc-url ... --private-key ... --callback ... --value ...` shape, convert to `DeployParams`, call `Runner::deploy()`, print result or error, exit. `main.rs` stays under 40 lines. Integration tests validate the full path against real Foundry on Sepolia.

**Delivers:** Complete binary `d2p` that passes the "looks done but isn't" checklist from PITFALLS.md: receipt status verified, bytecode confirmed, value applied, key not logged, correct chain.

**Addresses (features):** Single-command deployment, named flags, env var fallbacks, Foundry PATH check at startup, `--help` and `--version`.

**Implements (architecture):** cli.rs (clap derive hierarchy), main.rs entry point, integration tests with real forge/cast on Sepolia.

**Avoids (pitfalls):**
- Pitfall 5: `.env_clear()` in Command builder; `hide_env_values(true)` in clap; no key in error strings
- UX pitfall: Foundry PATH check at startup before any Command spawn

**Research flag:** No deeper research needed for CLI structure. Integration test against Lasna (Reactive Network) should be explicit acceptance criteria — this is the chain where the forge-to-cast fallback actually fires.

### Phase Ordering Rationale

- Phase 1 before Phase 2: types must exist before the functions that use them; prevents interface churn
- Phase 2 before Phase 3: deploy logic is the hard part; CLI is mechanical wiring; inverting the order means bugs hide behind argument parsing
- Phase 3 integrates Phase 1 + 2 into a binary and validates end-to-end; integration tests require a real Foundry installation and RPC access, so they come last
- All three pitfall mitigations that affect correctness (chain ID verification, receipt status check, value assertion) belong in Phase 2, not Phase 3 — they are part of the deploy contract, not CLI polish

### Research Flags

Phases with standard patterns (no deeper research needed):
- **Phase 1:** Rust stdlib patterns; direct reference in `tmp/edge-rs/`
- **Phase 2:** std::process::Command patterns are fully documented; Foundry pitfalls are documented with issue links in PITFALLS.md
- **Phase 3:** clap 4.5 derive is fully documented; in-repo reference in `tmp/edge-rs/cli.rs`

Phases that need integration validation (not research, but explicit test criteria):
- **Phase 3 acceptance:** Deploy to Lasna (Reactive Network) with a real UniswapV3Reactive bytecode to confirm the forge-to-cast fallback fires and the contract is funded. Without this test, the tool's core value proposition is unverified.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions verified against in-repo `tmp/edge-rs/Cargo.toml` (direct file read) and official crate pages; Rust 1.85 confirmed in edge-rs workspace |
| Features | HIGH | Table stakes derived from Foundry docs + hardhat-deploy patterns; anti-features and scope limits are explicit in PROJECT.md |
| Architecture | HIGH | Official clap docs, Rust stdlib docs, Rust CLI book — all cited with direct URLs; module structure mirrors edge-rs precedent in repo |
| Pitfalls | HIGH | All 6 critical pitfalls have corresponding Foundry GitHub issue numbers (verified); project MEMORY.md independently confirms the forge-to-cast fallback and callback gas findings |

**Overall confidence:** HIGH

### Gaps to Address

- **forge --json output availability:** STACK.md notes with MEDIUM confidence that `forge create --json` emits structured output. PITFALLS.md pitfall 2 contradicts this by noting `forge create` has no `--json` flag (only `forge script` does). During Phase 2, verify experimentally whether `forge create --json` is valid in Foundry v1.x. If it is not, the output parser must use prefix-matching ("Deployed to:") rather than JSON deserialization for the primary path.

- **cast send --create bytecode source:** ARCHITECTURE.md notes that `cast send --create` requires the bytecode as a hex argument. During Phase 2, determine whether d2p reads the bytecode from the compiled artifact (`out/` directory) or whether it relies on `forge build` having already been run and reads `foundry.toml` `out` field to locate the artifact. This is a build-order assumption that must be made explicit in the CLI help text.

- **Lasna chain ID for verification:** PITFALLS.md recommends verifying chain ID post-deployment, but the expected Lasna chain ID is not documented in the research. MEMORY.md provides the Lasna RPC (`https://lasna-rpc.rnk.dev`) but not the chain ID. Add the chain ID as a constant or query it on first invocation.

## Sources

### Primary (HIGH confidence)
- `tmp/edge-rs/Cargo.toml` — pinned dependency versions (clap 4.5.0, anyhow 1.0.79, thiserror 2.0, serde_json 1.0.113); in-repo direct file read
- [clap derive tutorial — docs.rs](https://docs.rs/clap/latest/clap/_derive/_tutorial/index.html) — subcommand hierarchy patterns
- [std::process::Command — Rust stdlib](https://doc.rust-lang.org/std/process/struct.Command.html) — subprocess invocation, environment control
- [Command Line Applications in Rust — machine communication](https://rust-cli.github.io/book/in-depth/machine-communication.html) — pipe-friendly output, exit codes
- [thiserror and anyhow — Comprehensive Rust](https://google.github.io/comprehensive-rust/error-handling/thiserror-and-anyhow.html) — error handling split

### Secondary (MEDIUM confidence)
- [Foundry issue #7564](https://github.com/foundry-rs/foundry/issues/7564) — --rpc-url ignored bug (cited by researchers)
- [Foundry issue #2508](https://github.com/foundry-rs/foundry/issues/2508) — exit code 0 on revert
- [Foundry issue #2123](https://github.com/foundry-rs/foundry/issues/2123) — --value ignored for payable constructors
- [Foundry issue #770](https://github.com/foundry-rs/foundry/issues/770) — --constructor-args position bug
- [Foundry issue #6050](https://github.com/foundry-rs/foundry/issues/6050) — output format change after version update
- [Rust CLI book — clap best practices](https://hemaks.org/posts/building-production-ready-cli-tools-in-rust-with-clap-from-zero-to-hero/) — env var fallback, exit codes
- [forge create reference](https://learnblockchain.cn/docs/foundry/i18n/en/reference/cli/forge/create.html) — --json, --legacy, --broadcast flags
- Project MEMORY.md — independently confirms forge-to-cast fallback and Lasna RPC endpoint

---
*Research completed: 2026-03-17*
*Ready for roadmap: yes*
