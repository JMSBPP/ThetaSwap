---
phase: 03-cli-wiring
verified: 2026-03-18T02:15:00Z
status: gaps_found
score: 7/8 must-haves verified
re_verification: false
gaps:
  - truth: "d2p ts reactive --help shows usage with a concrete example invocation"
    status: failed
    reason: "The long_about attribute on ReactiveArgs defines the example text but clap does not render it in any binary --help output path. The example (rpc.sepolia.org, --private-key $ETH_PRIVATE_KEY, --callback 0xcallback) is invisible to users. The test_help_contains_example passes only because 'd2p ts reactive' appears in the Usage line, not because the example is shown."
    artifacts:
      - path: "d2p/src/cli.rs"
        issue: "long_about on an embedded Args struct (ReactiveArgs, line 31) is not rendered by clap when the subcommand is invoked via a nested Subcommand enum. Both -h and --help produce identical short output with no example text."
    missing:
      - "Move the example text to a location clap will render: add an after_long_help or use #[command(after_help)] on ReactiveArgs, OR move the long_about to the TsCommands::Reactive variant doc comment (/// lines on the enum variant), OR add #[command(long_about)] on the Commands::Ts struct instead."
      - "Update test_help_contains_example to assert the example URL 'rpc.sepolia.org' or '--callback 0xcallback' is present in the rendered help output, not just the substring 'd2p ts reactive'."
human_verification:
  - test: "Full deploy via live CLI"
    expected: "d2p ts reactive uniswap-v3 --rpc-url <url> --private-key <key> --callback <addr> exits 0 and prints address + tx_hash on stdout, nothing else on stdout"
    why_human: "Requires live Foundry binaries and live RPC endpoint; cannot be verified without network access and deployed callback proxy"
---

# Phase 3: CLI Wiring Verification Report

**Phase Goal:** Complete `d2p` binary where `d2p ts reactive uniswap-v3` accepts all documented flags and env vars, invokes the Phase 2 runner, and exits cleanly
**Verified:** 2026-03-18T02:15:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|---------|
| 1 | `d2p ts reactive uniswap-v3 --rpc-url <url> --private-key <key> --callback <addr>` routes through all CLI layers and reaches Runner::deploy() | VERIFIED | main.rs:35 `Runner::new(params).deploy()?`; test_cli_routing passes; binary builds |
| 2 | ETH_RPC_URL and ETH_PRIVATE_KEY env vars are accepted when flags are omitted | VERIFIED | cli.rs:37,41 `#[arg(env = "ETH_RPC_URL")]`, `#[arg(env = "ETH_PRIVATE_KEY")]`; Cargo.toml has `"env"` feature; test_env_rpc_url and test_env_private_key both pass |
| 3 | Missing --callback with no env causes exit code 1 and an error on stderr, nothing on stdout | VERIFIED | `#[arg(long)] pub callback: String` (no default); binary exits 2 (clap parse error) with error on stderr; test_callback_required passes; exit code 2 is acceptable for parse errors per plan OUT-03 note |
| 4 | d2p --version prints the version from Cargo.toml | VERIFIED | `#[command(version)]` on Cli (cli.rs:5); binary outputs "d2p 0.1.0"; Cargo.toml version = "0.1.0" |
| 5 | d2p ts reactive --help shows usage with a concrete example invocation | FAILED | long_about is defined in cli.rs:31 but clap does not render it in binary output. Both `d2p ts reactive --help` and `d2p ts reactive uniswap-v3 --help` show only "Deploy a reactive contract" (short about). The example URL and flags are absent from all help paths. |
| 6 | --legacy does not appear as a user flag in any help text | VERIFIED | No `--legacy` field in any cli.rs struct; test_no_legacy_flag passes; binary help confirmed clean |
| 7 | Invalid --value (e.g. 'noreact') is rejected by clap before Runner::deploy() is called | VERIFIED | `value_parser = parse_value` on cli.rs:49; `d2p ... --value noreact` exits 2 with "invalid value 'noreact'" on stderr; parse_value tests pass |
| 8 | Non-existent --project path causes an actionable error before any forge/cast subprocess is spawned | VERIFIED | main.rs:25-26 `canonicalize().with_context(...)`; binary exits 1 with "project path does not exist: /tmp/nonexistent_path_xyz: No such file or directory" |

**Score:** 7/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `d2p/Cargo.toml` | clap with derive+env features | VERIFIED | Line 12: `clap = { version = "4.5", features = ["derive", "env"] }` |
| `d2p/src/cli.rs` | Cli, Commands, TsArgs, TsCommands, ReactiveArgs, Protocol, parse_value(); min 60 lines | VERIFIED | 211 lines; all 6 types exported; parse_value() defined at line 63; 8 unit tests |
| `d2p/src/main.rs` | Binary entry point wiring Cli::parse() -> DeployParams -> Runner::deploy() -> stdout/exit | VERIFIED | 41 lines; run()/main() split; full wiring complete |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `d2p/src/cli.rs ReactiveArgs` | `d2p/src/deploy/mod.rs DeployParams` | main.rs constructs DeployParams from ReactiveArgs fields | WIRED | main.rs:27-34 constructs `DeployParams { rpc_url: args.rpc_url, private_key: args.private_key, callback: args.callback, value: args.value, contract_path, project_dir }` — all 6 fields mapped |
| `d2p/src/main.rs run()` | `d2p/src/deploy/mod.rs Runner::deploy()` | Runner::new(params).deploy() | WIRED | main.rs:35: `Runner::new(params).deploy()?` — exact pattern required by plan |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|------------|------------|-------------|--------|---------|
| CMD-01 | 03-01-PLAN.md | `d2p ts reactive uniswap-v3` subcommand tree | SATISFIED | Nested Cli → Commands::Ts → TsCommands::Reactive → ReactiveArgs; test_cli_routing passes |
| CMD-02 | 03-01-PLAN.md | `--rpc-url` with ETH_RPC_URL env fallback | SATISFIED | `#[arg(long, env = "ETH_RPC_URL")]`; "env" feature in Cargo.toml; test_env_rpc_url passes |
| CMD-03 | 03-01-PLAN.md | `--private-key` with ETH_PRIVATE_KEY env fallback | SATISFIED | `#[arg(long, env = "ETH_PRIVATE_KEY")]`; test_env_private_key passes |
| CMD-04 | 03-01-PLAN.md | `--callback` required, no default | SATISFIED | `#[arg(long)] pub callback: String`; clap enforces required; test_callback_required passes |
| CMD-05 | 03-01-PLAN.md | `--value` human unit parsing, default "10react" | SATISFIED | parse_value() validates react/ether/gwei/wei units; default_value = "10react"; test_parse_value_* pass |
| CMD-06 | 03-01-PLAN.md | `--legacy` not user-supplied | SATISFIED | No --legacy field in any struct; test_no_legacy_flag passes |
| CMD-07 | 03-01-PLAN.md | `d2p ts reactive --help` shows concrete example | BLOCKED | long_about defined but not rendered in any binary help path; example text invisible to users |
| CMD-08 | 03-01-PLAN.md | `d2p --version` shows Cargo.toml version | SATISFIED | `#[command(version)]` on Cli; binary outputs "d2p 0.1.0" |
| CMD-09 | 03-01-PLAN.md | `--project` flag with CWD default; fails on bad path | SATISFIED | `#[arg(long, default_value = ".")]`; canonicalize() with actionable context |
| OUT-02 | 03-01-PLAN.md | stderr shows error on failure | SATISFIED | `eprintln!("error: {e:#}")` in main(); clap errors include Usage context; anyhow chain with_context adds path info |
| OUT-03 | 03-01-PLAN.md | Exit code 0 success, 1 failure | SATISFIED | `std::process::exit(1)` in main() error arm; clap exits 2 for parse errors (acceptable per plan note) |

**Orphaned requirements check:** REQUIREMENTS.md maps CMD-01 through CMD-09, OUT-02, OUT-03 to Phase 3. All 11 are claimed in 03-01-PLAN.md. No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `d2p/src/cli.rs` | 31 | `long_about` defined but not rendered by clap for embedded Args struct | Warning | CMD-07 example text defined but invisible to users at runtime |

No TODO/FIXME/placeholder comments, no empty implementations, no stub return values found in the modified files.

### Human Verification Required

#### 1. Full CLI Deploy End-to-End

**Test:** Run `d2p ts reactive uniswap-v3 --rpc-url <live_rpc> --private-key <key> --callback <addr>` against Sepolia or Lasna with forge and cast on PATH.
**Expected:** Exits 0; stdout contains exactly two lines (address, tx_hash); stderr contains only the fallback warning if primary fails; no diagnostic noise on stdout.
**Why human:** Requires live Foundry binaries, live RPC endpoint, funded deployer account, and a deployed callback proxy contract.

### Gaps Summary

One gap blocks full CMD-07 satisfaction: the concrete example invocation defined in `long_about` on `ReactiveArgs` is invisible to users because clap does not render `long_about` from embedded `Args` structs in nested subcommand hierarchies. The attribute is present in source code and the test passes, but passing the test requires only that "d2p ts reactive" appears in the Usage line — not that the example (with `--rpc-url https://rpc.sepolia.org`, etc.) is visible. A user running `d2p ts reactive --help` sees no example.

The fix is straightforward: either use `#[command(after_help = "...")]` on `ReactiveArgs` (which clap renders unconditionally), or add the example as a doc comment on the `TsCommands::Reactive` enum variant so it appears in `d2p ts --help`.

All other 10 requirements (CMD-01 through CMD-06, CMD-08, CMD-09, OUT-02, OUT-03) are fully satisfied. The binary builds, all 28 tests pass, env var fallback works, parse_value rejects invalid units before Runner is called, and non-existent --project paths produce actionable errors.

---

_Verified: 2026-03-18T02:15:00Z_
_Verifier: Claude (gsd-verifier)_
