---
status: complete
phase: 03-cli-wiring
source: 03-01-SUMMARY.md
started: 2026-03-18T01:30:00Z
updated: 2026-03-18T01:45:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Version Output
expected: Run `cd d2p && cargo build --quiet && ./target/debug/d2p --version` — should print `d2p 0.1.0`
result: pass

### 2. Help with Example
expected: Run `cd d2p && ./target/debug/d2p ts reactive --help` — should show all flags (--rpc-url, --private-key, --callback, --value, --project) and an Example section at the bottom with `rpc.sepolia.org`
result: pass

### 3. Missing Callback Error
expected: Run `cd d2p && ./target/debug/d2p ts reactive uniswap-v3 --rpc-url http://x --private-key 0xk` — should exit non-zero with error about missing --callback on stderr, nothing on stdout
result: pass

### 4. Invalid Value Rejected
expected: Run `cd d2p && ./target/debug/d2p ts reactive uniswap-v3 --rpc-url http://x --private-key 0xk --callback 0xc --value noreact` — should exit non-zero with error about invalid value format
result: pass

### 5. Env Var Fallback
expected: Run `ETH_RPC_URL=http://from-env d2p/target/debug/d2p ts reactive uniswap-v3 --private-key 0xk --callback 0xc --project /tmp` — should NOT complain about missing --rpc-url (env var accepted as fallback). Will fail at deployment stage (no forge), but that's expected — the test confirms env parsing works.
result: pass

### 6. Full Test Suite
expected: Run `cd d2p && cargo test` — should show `test result: ok. 28 passed; 0 failed`
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0

## Gaps

[none]

## Notes

- Foundry does not recognize "react" as a --value denomination. `forge create --value 10react` fails. CLI validates the suffix but Foundry rejects downstream. For live deploys, use `--value 10ether` or raw wei. Consider adding react→wei conversion in v1.x.
