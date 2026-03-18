# D2P CLI — ThetaSwap Deployment Pipeline

## What This Is

A Rust CLI tool (`d2p`) that wraps Foundry's `forge create` and `cast send --create` to deploy ThetaSwap reactive contracts. Ships as `d2p ts reactive uniswap-v3` — a pipe-friendly deployment wrapper that handles Foundry quirks with automatic fallback. 1,011 lines of Rust, 28 tests, zero external runtime dependencies.

## Core Value

Reliable single-command deployment of reactive contracts with automatic fallback when `forge create` fails — always get a deployed address or a clear error.

## Requirements

### Validated

- ✓ `d2p ts reactive uniswap-v3` deploys UniswapV3Reactive — v1.0
- ✓ CLI accepts `--rpc-url`, `--private-key`, `--callback`, `--value`, `--project` flags — v1.0
- ✓ Primary path: `forge create` with `--broadcast --legacy` baked in — v1.0
- ✓ Fallback path: `cast send --create` on forge failure — v1.0
- ✓ Stdout: deployed address + tx hash (pipe-friendly) — v1.0
- ✓ Stderr: error messages, non-zero exit — v1.0
- ✓ Env var fallback: `ETH_RPC_URL`, `ETH_PRIVATE_KEY` — v1.0
- ✓ Human-friendly `--value` parsing (10react, 0.01ether) — v1.0
- ✓ Post-deploy receipt verification (`cast receipt --json`) — v1.0
- ✓ Foundry PATH check on startup — v1.0

### Active

(None — planning next milestone)

### Out of Scope

- Other `d2p ts` subcommands beyond `reactive` — future milestone
- Protocol support beyond `uniswap-v3` — future milestone (structure allows it)
- Contract verification (etherscan/blockscout) — use `forge verify-contract`
- Interactive prompts or TUI — pipe-friendly CLI
- Wallet/keystore integration — raw private key via flag/env
- `--json` output mode — v1.x
- `react` → wei unit conversion (Foundry doesn't recognize "react") — v1.x

## Context

- Shipped v1.0 with 1,011 LOC Rust in `d2p/` directory
- Tech stack: clap 4.5, anyhow 1.x, thiserror 2.x, serde/serde_json
- 28 unit tests covering arg parsing, fallback logic, receipt verification
- Foundry "react" denomination not supported — use "ether" or raw wei for now

## Constraints

- **Language**: Rust
- **Dependencies**: `forge` and `cast` on PATH (Foundry toolchain)
- **Build**: `foundry.toml` at project root for Solidity compilation
- **Output**: Address + tx hash on stdout, errors on stderr

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Rust for CLI | Single binary, no runtime | ✓ Good |
| forge create primary, cast send fallback | forge create sometimes ignores --rpc-url | ✓ Good |
| --legacy baked into forge create only | Required for Lasna; not needed for cast send | ✓ Good |
| run()/main() split pattern | Full control over stderr format and exit codes | ✓ Good |
| parse_value() free function | No third-party crate needed for unit validation | ✓ Good |
| after_help for examples | long_about not rendered in nested subcommands | ✓ Good (fixed during UAT) |

---
*Last updated: 2026-03-18 after v1.0 milestone*
