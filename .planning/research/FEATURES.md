# Feature Research

**Domain:** Smart contract deployment CLI (Rust, wrapping Foundry toolchain)
**Researched:** 2026-03-17
**Confidence:** HIGH (table stakes derived from Foundry docs + hardhat-deploy patterns); MEDIUM (differentiators from Rust CLI community patterns)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Single-command deployment | Every deployment tool since Truffle ships this; anything less is not a CLI, it's a script | LOW | `d2p ts reactive uniswap-v3 --rpc-url ... --private-key ... --callback ...` |
| Named flags for all required inputs | Positional args are unusable in CI pipelines; forge create itself uses `--rpc-url`, `--private-key` | LOW | `--rpc-url`, `--private-key`, `--callback`, `--value` |
| Stdout = deployed address + tx hash | Every deploy tool from hardhat-deploy to forge create outputs the address; piping to scripts requires stable stdout | LOW | One line each on stdout; nothing else on stdout path |
| Stderr = errors, non-zero exit on failure | POSIX convention; `set -e` shell scripts depend on it; forge create violates this occasionally | LOW | All diagnostic noise to stderr; exit 1 on any failure |
| Environment variable fallback for secrets | Private keys must never be logged; env var fallback (`ETH_PRIVATE_KEY`, `ETH_RPC_URL`) is standard Foundry convention | LOW | Env vars read when flags absent; flag always wins over env |
| `--help` and `--version` | clap generates these for free; users immediately try `--help` before reading docs | LOW | clap derive handles this; version from `Cargo.toml` |
| Clear error messages with context | forge create sometimes silently fails or emits misleading output; users need to know what went wrong and why | MEDIUM | Show which command was attempted, what response was received |
| `--legacy` flag support (or bake it in) | Reactive Network (Lasna) requires legacy transactions; missing this = silent deployment failure on target chain | LOW | Bake it in for reactive subcommand; don't make user remember it |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Automatic forge-create → cast-send fallback | forge create silently ignores `--rpc-url` in some Foundry builds; automatic retry with `cast send --create` means deployments succeed where bare forge fails | MEDIUM | Core value of d2p per PROJECT.md; detect failure by checking for address in stdout, not exit code |
| `--json` output mode | Enables downstream tooling to parse address + tx hash without brittle grep/awk; follows forge create's own `--json` pattern | LOW | `{"address": "0x...", "tx": "0x..."}` on stdout; add `--json` flag |
| Subcommand structure for future protocols | `d2p ts reactive <protocol>` already namespaces correctly; adding `uniswap-v4`, `chainlink` later requires zero CLI redesign | LOW | clap subcommand tree set up now; cost is near zero up front |
| Foundry PATH check on startup | Users run `d2p` on fresh machines; missing `forge`/`cast` gives confusing error ("forge: command not found" buried in stderr); explicit check gives actionable message | LOW | `which forge && which cast` equivalent at startup; fail with "Install Foundry: https://getfoundry.sh" |
| Payable value flag with human-friendly units | UniswapV3Reactive constructor is payable; `--value 0.01ether` is friendlier than `--value 10000000000000000`; cast handles unit parsing | LOW | Parse with cast's unit conventions; forward raw wei to command |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems — deliberately exclude from this milestone.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Interactive prompts / TUI | Reduces user effort for flags they don't know | Breaks pipe usage; breaks CI; breaks scripting; `d2p ... | xargs ...` fails with interactive stdin | Excellent `--help` text with examples instead |
| Deployment artifact storage (JSON registry) | hardhat-deploy does this; users want a record of deployed addresses | Requires file I/O, path management, format versioning, merge conflicts in git; scope explosion for a thin wrapper | Pipe stdout to a file: `d2p ts reactive uniswap-v3 ... > deploy.json` |
| Etherscan / Blockscout verification | Post-deploy verification is a natural next step | Requires API key management, chain-specific endpoints, retry logic, separate verification status polling; doubles scope | Use `forge verify-contract` directly after deploy; PROJECT.md explicitly lists this as out of scope |
| Wallet / keystore management (hardware or file) | Ledger/Trezor support is a legitimate security ask | Adds heavy dependencies (hidapi, usb), platform-specific build requirements, breaks Linux CI; raw private key via env var is sufficient for scripted reactive deploys | Document use of `cast wallet` or `--account` flag if Foundry adds first-class support later |
| Dry-run / simulation mode | Users want to preview what would happen | forge script already does this better natively (Solidity simulation, state diffs, gas estimates); duplicating it in d2p is wasted effort | Instruct users to run `forge script` for simulation, `d2p` for actual deploy |
| Multi-contract orchestration | "Deploy everything at once" is appealing | One reactor + one callback address is the entire deploy surface for this milestone; orchestration belongs in forge script, not a thin wrapper | Keep d2p atomic; chain multiple invocations in shell scripts if needed |
| Config file (TOML/YAML) | Avoids long flag lists | Adds config file location discovery, merging logic, schema validation; for a 4-flag CLI this is pure overhead | Shell aliases or `.env` files cover the use case at zero implementation cost |

---

## Feature Dependencies

```
[Named flags + env var fallback]
    └──required by──> [Single-command deployment]
                          └──required by──> [forge→cast fallback]
                                                └──required by──> [JSON output mode]

[Foundry PATH check]
    └──enhances──> [Clear error messages]

[Subcommand structure]
    └──enables──> [Future protocol support] (uniswap-v4, etc.)

[--legacy baked in]
    └──required by──> [Successful Lasna deployment]
    └──part of──> [Single-command deployment]

[Interactive prompts] ──conflicts──> [Pipe-friendly stdout]
[Deployment artifact storage] ──conflicts with scope of──> [Thin wrapper]
```

### Dependency Notes

- **Named flags requires env var fallback first:** The flag parser (clap) must define env fallbacks at struct definition time; this is zero extra code with clap's `env` attribute, so both ship together.
- **forge→cast fallback requires named flags:** The fallback re-uses the same parsed flag values to construct the `cast send --create` invocation; flags must be parsed before the fallback logic runs.
- **JSON output enhances forge→cast fallback:** If fallback fires, the output format must still be stable JSON (or plain address+txhash); the fallback implementation must write to the same output path.
- **Interactive prompts conflicts with pipe-friendly stdout:** Prompts write to stdout or stderr in a way that breaks line-oriented parsing. This is an architectural conflict, not a priority conflict — both cannot coexist.

---

## MVP Definition

### Launch With (v1)

Minimum viable product for this milestone.

- [ ] `d2p ts reactive uniswap-v3` subcommand — the entire stated scope of this milestone
- [ ] `--rpc-url`, `--private-key`, `--callback`, `--value` flags with env var fallbacks — required to invoke deployment at all
- [ ] `--legacy` baked in for reactive subcommand — required for Lasna; missing it means broken deployments
- [ ] Primary path: `forge create` with `--broadcast --legacy` — happy path
- [ ] Fallback path: `cast send --create` on `forge create` failure — core differentiator, core stated value
- [ ] Stdout: address + tx hash on success — pipe-friendly output contract
- [ ] Stderr: error message on failure, exit 1 — POSIX contract
- [ ] Foundry PATH check on startup — prevents confusing UX on fresh machines

### Add After Validation (v1.x)

Add once the deploy path is confirmed working end-to-end.

- [ ] `--json` output flag — add when a downstream consumer (script, CI step) actually needs structured output; trivial to add
- [ ] Payable value unit parsing (`0.01ether` → wei) — add if users complain about raw wei; cast can do the conversion

### Future Consideration (v2+)

Defer until the subcommand surface grows.

- [ ] `d2p ts reactive uniswap-v4` — natural extension; subcommand structure already supports it; add when UniswapV4Facet deployment is a milestone
- [ ] Additional `d2p ts` subcommands (non-reactive) — future milestones per PROJECT.md

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Single-command deploy (`d2p ts reactive uniswap-v3`) | HIGH | LOW | P1 |
| Named flags + env var fallback | HIGH | LOW | P1 |
| `--legacy` baked in | HIGH | LOW | P1 |
| forge→cast automatic fallback | HIGH | MEDIUM | P1 |
| Stdout address+txhash / stderr errors | HIGH | LOW | P1 |
| Exit codes (0/1) | HIGH | LOW | P1 |
| Foundry PATH check | MEDIUM | LOW | P1 |
| `--json` output mode | MEDIUM | LOW | P2 |
| Payable value unit parsing | LOW | LOW | P2 |
| `d2p ts reactive uniswap-v4` | MEDIUM | LOW | P3 |
| Deployment artifact storage | LOW | HIGH | OUT |
| Etherscan verification | LOW | HIGH | OUT |
| Interactive TUI | LOW | HIGH | OUT |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration
- OUT: Explicitly excluded from scope

---

## Competitor Feature Analysis

| Feature | forge create (raw) | hardhat-deploy | d2p (this project) |
|---------|-------------------|----------------|-------------------|
| Single command deploy | YES | YES (script-based) | YES |
| Auto-fallback on RPC failure | NO | NO | YES (core differentiator) |
| Pipe-friendly stdout | PARTIAL (noisy by default) | NO (human-readable logs) | YES (address+txhash only) |
| `--legacy` for reactive chains | Manual flag each time | Plugin config | Baked in for `ts reactive` |
| Deployment artifact registry | NO (forge script does) | YES | NO (out of scope) |
| JSON output | YES (`--json`) | NO | YES (`--json` flag, v1.x) |
| Multi-contract orchestration | NO (forge script does) | YES | NO (out of scope) |
| Verification | YES (`forge verify-contract`) | YES (plugin) | NO (out of scope) |
| Env var fallback for secrets | YES (`ETH_PRIVATE_KEY`) | YES | YES |
| Rust binary, no JS runtime | YES | NO | YES |

---

## Sources

- [Foundry forge create reference](https://learnblockchain.cn/docs/foundry/i18n/en/reference/cli/forge/create.html) — CLI flags, `--json`, `--legacy`, `--broadcast`
- [Announcing Foundry v1.0](https://www.paradigm.xyz/2025/02/announcing-foundry-v1-0) — current Foundry state (Feb 2025)
- [Foundry Scripting guide](https://getfoundry.sh/forge/deploying/) — forge script vs forge create distinction
- [hardhat-deploy GitHub](https://github.com/wighawag/hardhat-deploy) — artifact registry, named accounts, chain management patterns
- [Rust CLI machine communication guide](https://rust-cli.github.io/book/in-depth/machine-communication.html) — pipe-friendly output, `--json`, NO_COLOR
- [Clap Rust CLI best practices](https://hemaks.org/posts/building-production-ready-cli-tools-in-rust-with-clap-from-zero-to-hero/) — env var fallback, exit codes, shell completions
- [Foundry RPC URL issues](https://github.com/foundry-rs/foundry/issues) — forge create RPC silent-ignore bug history
- [Hardhat vs Foundry 2025](https://markaicode.com/hardhat-vs-foundry-comparison-2025/) — ecosystem positioning

---
*Feature research for: Rust CLI smart contract deployment wrapper (d2p)*
*Researched: 2026-03-17*
