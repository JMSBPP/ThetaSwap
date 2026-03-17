# Pitfalls Research

**Domain:** Rust CLI wrapping Foundry (forge/cast) for smart contract deployment
**Researched:** 2026-03-17
**Confidence:** HIGH (verified against official Foundry GitHub issues and Rust stdlib docs)

## Critical Pitfalls

### Pitfall 1: `forge create` Silently Ignores `--rpc-url` on Some Networks

**What goes wrong:**
`forge create` accepts the `--rpc-url` flag without error but actually uses an internally cached or default endpoint instead. The deployment proceeds, tx hash is emitted — but against the wrong chain. This is a confirmed, documented Foundry bug (issue #7564: `--rpc-url` option is ignored by rpc cheatcodes; also observed in forge create workflows against custom RPC endpoints).

**Why it happens:**
Foundry caches RPC configuration in multiple places (env var `ETH_RPC_URL`, foundry.toml `[rpc_endpoints]`, forge's internal profile resolution). When `--rpc-url` is passed as a subprocess flag, the internal resolution pipeline may override it with a cached value before the actual request is made. The CLI arg and the internal config disagree silently.

**How to avoid:**
This is the explicit reason `d2p` uses `cast send --create` as its primary or fallback path. `cast send` is a lower-level command that does not perform the same multi-source RPC resolution. When building the subprocess invocation:
- Pass `--rpc-url` via `.arg()` on the `Command` builder, not via the inherited environment
- Remove `ETH_RPC_URL` from the child process environment with `.env_remove("ETH_RPC_URL")` before spawning
- After deployment, verify the chain ID of the returned tx hash with a `cast chain-id --rpc-url <url>` call and compare to what was expected

**Warning signs:**
- Deployment succeeds but the returned address has no bytecode on the intended network
- Transaction hash is not found on the expected block explorer
- Output shows a deployer nonce that doesn't match the wallet's state on the target RPC

**Phase to address:**
Subprocess invocation layer — the phase that builds the `Command` struct for both `forge create` and `cast send`. Implement `env_remove("ETH_RPC_URL")` and chain-ID verification before declaring success.

---

### Pitfall 2: Parsing `forge create` Output with Fixed Regex Breaks on Forge Updates

**What goes wrong:**
`forge create` stdout format is:
```
Deployer: 0x...
Deployed to: 0x...
Transaction hash: 0x...
```
Developers write a regex against these exact labels. Foundry has changed this format in minor releases without warning (issue #6050: deserialization errors after forge version updates). A Forge update mid-project silently changes "Deployed to:" to "Contract address:" or alters whitespace, causing the Rust parser to return `None` and the CLI to emit a false failure.

**Why it happens:**
`forge create` output is human-readable prose, not a structured format. There is no `--json` flag for `forge create` (only for `forge script`). The output is an implementation detail that Foundry can change without a semver bump.

**How to avoid:**
- Parse for the Ethereum address pattern (`0x[0-9a-fA-F]{40}`) that follows whatever label appears on the "deployed contract" line, not for the specific label text
- Accept both "Deployed to:" and "Contract address:" as valid prefixes
- If the primary parse fails but the exit code is 0, fall through to `cast receipt <txhash> --field contractAddress` to recover the address from the RPC
- Pin the `forge` version used in CI/CD and test the parse on every version upgrade

**Warning signs:**
- CLI returns "could not parse deployed address" after a `foundryup` run
- `forge create` exits 0 but the Rust code path treats it as failure
- Different output on CI (where foundryup installs latest) than on dev machines

**Phase to address:**
Output parsing module — implement the fallback recovery path (`cast receipt`) at the same time as the primary parser, not as a later improvement.

---

### Pitfall 3: `--value` Flag Not Forwarded to Payable Constructor via `cast send --create`

**What goes wrong:**
`UniswapV3Reactive` has a payable constructor that calls `depositToSystem` with `msg.value`. When `cast send --create` is used as the fallback path, forgetting to append `--value <wei>` causes the constructor to execute with `msg.value == 0`. The transaction may succeed (no revert if `depositToSystem` accepts zero) but the reactive contract is unfunded and will fail at runtime when the Reactive Network tries to trigger callbacks.

There is also a documented historical bug in `forge create` (issue #2123) where `--value` was silently ignored for payable constructors. The fallback path must explicitly carry the value flag.

**Why it happens:**
`--value` is an optional flag that looks like an optional configuration detail. Developers focus on getting the contract address and tx hash and miss that the funding step is part of deployment, not post-deployment.

**How to avoid:**
- Treat `--value` as required for UniswapV3Reactive deployment, not optional
- Validate at CLI startup: if `--value` is missing or zero, emit a warning to stderr before attempting deployment
- After deployment, call `cast balance <deployed_address> --rpc-url <url>` and assert it equals the supplied `--value`
- In the `Command` builder, assert that `--value` is present in the args list before spawning either `forge create` or `cast send --create`

**Warning signs:**
- Deployed contract has zero ETH balance immediately after deployment
- Reactive Network callbacks fail with "insufficient funds" or are never triggered
- The `--value` flag present in `d2p` help text but not enforced in the subprocess builder

**Phase to address:**
Both the `forge create` invocation builder and the `cast send --create` fallback builder — value must be threaded through both code paths explicitly.

---

### Pitfall 4: `--constructor-args` Position Sensitivity in `forge create`

**What goes wrong:**
`forge create` has a documented positional parsing bug (issue #770): `--constructor-args` must be placed after `--private-key` and the contract specifier, or Foundry raises "The following required arguments were not provided: `<CONTRACT>`". The Rust code that assembles the argument list must respect this ordering. Getting it wrong produces a cryptic Foundry error, not a deployment failure, so it is easy to misdiagnose.

**Why it happens:**
`--constructor-args` accepts multiple values (variadic). Clap (Foundry's arg parser) and the shell misinterpret subsequent positional arguments as constructor args when this flag appears too early. The issue is in Foundry's arg parser, not the shell, so quoting does not fix it.

**How to avoid:**
- Always build the `Command` arg list in this order: `forge create <CONTRACT_PATH> --rpc-url ... --private-key ... --legacy --broadcast --value ... --constructor-args <args...>`
- `--constructor-args` must be last
- Write a unit test that asserts the arg list order without spawning a process (inspect the `Command` args as a `Vec<OsString>`)

**Warning signs:**
- Error message "required arguments were not provided: CONTRACT" when the contract path is clearly set
- Works when args are reordered manually but fails via the CLI wrapper
- Only fails when constructor args are present (zero-arg contracts work fine)

**Phase to address:**
`forge create` command builder, before any integration testing. This is a pure construction bug, not a runtime/network bug.

---

### Pitfall 5: Private Key Leaked via `/proc/<pid>/cmdline` and Child Process Environment

**What goes wrong:**
`--private-key` passed as a `Command` argument is visible to any process on the system that can read `/proc/<pid>/cmdline` during the subprocess lifetime. On Linux, this window is small but non-zero. More critically, if the Rust process itself inherits `PRIVATE_KEY` from the shell environment and that variable is forwarded to the subprocess without explicit filtering, it persists in the child's environment as well.

**Why it happens:**
`std::process::Command` inherits the full parent environment by default. If the user runs `export PRIVATE_KEY=0x...` and the Rust CLI reads it as a clap `env` fallback, that variable is then forwarded unmodified to `forge`/`cast`, which may log it or re-export it internally.

**How to avoid:**
- Use `.env_clear()` on the `Command` builder then explicitly set only required env vars (PATH, HOME, necessary RPC env vars)
- Never log the private key; use `secrecy::Secret<String>` or equivalent to prevent accidental debug-format exposure
- For the `--private-key` flag, prefer accepting it via an environment variable that is consumed and cleared before the subprocess is spawned, not forwarded
- Document in help text: "prefer setting D2P_PRIVATE_KEY env var; value is consumed and not forwarded to subprocess"

**Warning signs:**
- `--private-key` value visible in `ps aux` output during deployment
- Rust debug logging (`RUST_LOG=debug`) printing the private key value
- CI logs capturing the full command including key

**Phase to address:**
CLI argument definition phase (clap setup). Mark the private key field with `hide_env_values(true)` in clap to prevent it from appearing in help output, and `.env_clear()` in the subprocess builder.

---

### Pitfall 6: Treating Exit Code 0 as Deployment Confirmation

**What goes wrong:**
Both `forge create` and `cast send` can exit 0 while the deployment failed. Documented cases include:
- `forge script --json` always returns exit code 0 regardless of revert (issue #2508)
- `forge create` exits 0 when the tx is submitted but the constructor reverts on-chain (the tx mines but fails)
- `cast send --create` exits 0 if the tx is broadcast, even if it reverts

The `d2p` CLI's pipe-friendly contract requires that a printed address means a live, deployed contract. If exit code 0 is used as the signal, address gets printed, downstream script uses it, and the contract does not exist.

**How to avoid:**
- Never rely on exit code alone
- After parsing the tx hash from output, call `cast receipt <txhash> --field status --rpc-url <url>` and assert the receipt status is `0x1` (success)
- Only then print the address to stdout
- If status is `0x0`, exit with non-zero code and print the revert reason to stderr

**Warning signs:**
- Address is printed but calling any function on it fails with "execution reverted"
- `cast code <address>` returns `0x` (no bytecode deployed)
- Downstream scripts receive an address but subsequent transactions fail

**Phase to address:**
Post-deployment verification step, before printing final output. This step must exist in both the `forge create` path and the `cast send --create` fallback path.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `inherit()` for all subprocess streams | No plumbing required; forge output visible in terminal | Cannot parse deployed address; cannot route errors to stderr properly | Never for production path |
| Regex on exact Foundry label strings | Simple to implement | Breaks on Foundry updates silently | Only if pinning exact forge version in lock file |
| Skipping receipt status check | Faster deployment loop | Silent deployment failures; broken downstream scripts | Never — this is the correctness guarantee |
| Single code path (no forge create / cast fallback) | Simpler code | Fails on Reactive Network Lasna where forge create ignores RPC | Never — fallback is the stated core value |
| Forwarding full parent env to subprocess | No extra code | Private key leakage, unexpected RPC override via ETH_RPC_URL | Never for security-sensitive subprocesses |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `forge create` RPC resolution | Trusting `--rpc-url` is used | Remove `ETH_RPC_URL` from child env; verify chain ID post-deployment |
| `cast send --create` bytecode | Assuming forge artifact path is stable | Resolve artifact path from `foundry.toml` `out` field at runtime, not hardcoded |
| Reactive Network (Lasna) | Forgetting `--legacy` flag | Bake `--legacy` into both code paths unconditionally |
| Payable constructor funding | Treating `--value` as optional | Validate and require `--value` at arg parse time; verify balance post-deploy |
| forge stdout parsing | Reading from `output().stdout` after process exits | Set `stdout(Stdio::piped())` before spawning; do not use `output()` if you also want stderr visible |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Waiting for `forge create` compilation on every deploy | Slow deployments (30-60s) when contract unchanged | Pre-build with `forge build` in a setup step; deploy from cached artifact | Every invocation — compilation overhead is always present |
| Spawning `cast` for each verification call sequentially | 3-5 second delay per post-deploy check | Batch: receipt status + bytecode + balance in parallel async calls | Single-threaded sequential subprocess calls |
| Re-reading foundry.toml on every command | File I/O overhead on hot paths | Parse once at startup, cache in struct | Not an issue at current scale; note for future if d2p spawns multiple deployments |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Printing `--private-key` value in error messages | Key extraction from logs | Never include arg values in error strings; use placeholder `[REDACTED]` |
| Inheriting full parent environment in subprocess | ETH_RPC_URL override; key forwarding | `Command::env_clear()` then selectively set PATH, HOME only |
| Accepting private key via `--private-key` positional arg (not env var) | Key visible in `ps aux`, shell history, CI logs | Accept via env var `D2P_PRIVATE_KEY`; read and zero memory before subprocess spawn |
| Logging subprocess full command at INFO level | Key visible in structured logs | Log command at TRACE with key replaced by `0x[REDACTED]`; only log at INFO if no sensitive args present |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Printing raw Foundry output instead of structured address+hash | Users get walls of text; breaks pipe usage | Capture all forge/cast output; print only address and tx hash to stdout on success; forward forge diagnostic output to stderr |
| Failing silently when forge/cast not on PATH | User sees no error, hangs, or gets OS "not found" without context | At startup, call `which forge` and `which cast`; if either absent, print actionable error: "forge not found — install Foundry: https://getfoundry.sh" |
| No fallback indication | User doesn't know forge failed and cast was used | Print `[warn] forge create failed, retrying with cast send --create` to stderr so the user knows which path succeeded |
| Non-zero exit code with no message | Scripts fail with no diagnostic | Any non-zero exit must be accompanied by a human-readable stderr message explaining what failed and what was attempted |

## "Looks Done But Isn't" Checklist

- [ ] **Deployment succeeds:** Verify `cast receipt <txhash> --field status` returns `0x1`, not just exit code 0
- [ ] **Address is live:** Verify `cast code <address>` returns non-empty bytecode before printing address to stdout
- [ ] **Value was applied:** Verify `cast balance <address>` equals supplied `--value` if contract is payable
- [ ] **Correct network:** Verify `cast chain-id` via the used RPC matches expected chain before deployment
- [ ] **forge not primary:** Fallback to `cast send --create` is triggered and tested, not just coded
- [ ] **Stderr clean:** Success output on stdout only; no Foundry progress lines polluting stdout
- [ ] **Key not logged:** `RUST_LOG=debug` run does not expose private key in any log line

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Wrong chain deployment (RPC ignored) | HIGH | Check both chains; if bytecode exists on wrong chain, re-deploy with corrected env; notify team of stray contract |
| Address printed but constructor reverted | MEDIUM | `cast code <address>` returns `0x`; safe to redeploy (no state); find revert reason via `cast run <txhash>` |
| Value not sent to payable constructor | MEDIUM | Cannot recover funds already in zero-balance contract; redeploy with correct `--value`; treat old address as dead |
| Private key exposed in logs | HIGH | Rotate key immediately; sweep funds to new address; audit what downstream systems received the logs |
| forge output format changed after update | LOW | Pin forge version in CI; roll back foundryup; update parser to handle new format; re-deploy |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| forge create ignores `--rpc-url` | Subprocess builder (Phase: invoke layer) | Integration test: deploy to Sepolia, verify contract exists on Sepolia not mainnet |
| Output parsing breaks on Forge updates | Output parser + fallback (Phase: output parsing) | Unit test: parse both old and new format strings; integration test after any foundryup |
| `--value` not forwarded to payable constructor | Command builder for both paths (Phase: arg assembly) | Post-deploy: `cast balance <address>` assertion in test suite |
| `--constructor-args` position bug | Command builder unit test (Phase: arg assembly) | Unit test asserting arg order in `Vec<OsString>` without spawning |
| Private key leakage | CLI arg definition (Phase: clap setup) | Security review: `RUST_LOG=debug` run produces no key in output |
| Exit code 0 = success false positive | Post-deploy verifier (Phase: verification step) | Integration test: deploy known-reverting constructor, assert d2p exits non-zero |

## Sources

- [Foundry issue #7564: `--rpc-url` ignored by rpc cheatcodes](https://github.com/foundry-rs/foundry/issues/7564)
- [Foundry issue #2508: `forge script --json` always returns zero exit code](https://github.com/foundry-rs/foundry/issues/2508)
- [Foundry issue #2123: `forge create` ignores `--value` for payable constructors](https://github.com/foundry-rs/foundry/issues/2123)
- [Foundry issue #770: `--constructor-args` only works if specified before `--private-key`](https://github.com/foundry-rs/foundry/issues/770)
- [Foundry issue #6050: deserialization error after forge version update](https://github.com/foundry-rs/foundry/issues/6050)
- [Foundry issue #1384: `--constructor-args-path` appends unexpected whitespace bytes](https://github.com/foundry-rs/foundry/issues/1384)
- [Rust std::process::Command documentation — environment inheritance and Stdio piping](https://doc.rust-lang.org/std/process/struct.Command.html)
- [Rust forum: display and capture stdout/stderr from a Command](https://users.rust-lang.org/t/display-and-capture-stdout-and-stderr-from-a-command/81296)
- [Leapcell: Secure Configuration and Secrets Management in Rust](https://leapcell.io/blog/secure-configuration-and-secrets-management-in-rust-with-secrecy-and-environment-variables)
- [Rust CLI book: Output for humans and machines](https://rust-cli.github.io/book/tutorial/output.html)
- [Project memory: forge create --rpc-url sometimes ignored; cast send --create more reliable](project memory — MEMORY.md `003 Reactive Integration Key Findings`)

---
*Pitfalls research for: Rust CLI (d2p) wrapping Foundry forge/cast for reactive contract deployment*
*Researched: 2026-03-17*
