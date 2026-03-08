"""Comparison harness: on-chain vs off-chain FCI convergence check.

Polls the Sepolia ReactiveAdapter's ``getIndex()`` and compares against
off-chain oracle fixture snapshots produced by ``fci_oracle.py``.
"""
from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from typing import Final

import httpx

# ── ABI constants ────────────────────────────────────────────────────────────
# getIndex() selector: keccak256("getIndex()")[:4]
GET_INDEX_SELECTOR: Final[str] = "0xc5b7e060"

WORD: Final[int] = 32  # bytes per ABI word


# ── Pure helpers ─────────────────────────────────────────────────────────────

def parse_index_response(hex_data: str) -> tuple[int, int, int]:
    """ABI-decode ``(uint128 indexA, uint256 thetaSum, uint256 posCount)``
    from the raw hex return of ``getIndex()``.

    *hex_data* is ``0x``-prefixed, 96 bytes (3 x 32-byte words).
    """
    raw = hex_data.removeprefix("0x")
    if len(raw) != WORD * 3 * 2:
        raise ValueError(
            f"Expected {WORD * 3 * 2} hex chars, got {len(raw)}"
        )
    index_a = int(raw[0:64], 16)
    theta_sum = int(raw[64:128], 16)
    pos_count = int(raw[128:192], 16)
    return index_a, theta_sum, pos_count


@dataclass(frozen=True, slots=True)
class ConvergenceResult:
    """Outcome of a single on-chain / off-chain comparison."""

    passed: bool
    drift: float
    on_chain_index: int
    off_chain_index: int


def check_convergence(
    *,
    on_chain_index: int,
    off_chain_index: int,
    epsilon: float,
) -> ConvergenceResult:
    """Compute relative drift and decide pass/fail against *epsilon*."""
    denom = max(on_chain_index, off_chain_index, 1)
    drift = abs(on_chain_index - off_chain_index) / denom
    return ConvergenceResult(
        passed=drift < epsilon,
        drift=drift,
        on_chain_index=on_chain_index,
        off_chain_index=off_chain_index,
    )


# ── IO helpers ───────────────────────────────────────────────────────────────

def poll_on_chain(
    rpc_url: str,
    adapter_address: str,
) -> tuple[int, int, int]:
    """Call ``getIndex()`` on *adapter_address* via JSON-RPC ``eth_call``."""
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [
            {"to": adapter_address, "data": GET_INDEX_SELECTOR},
            "latest",
        ],
    }
    resp = httpx.post(rpc_url, json=payload, timeout=30)
    resp.raise_for_status()
    body = resp.json()
    if "error" in body:
        raise RuntimeError(f"RPC error: {body['error']}")
    return parse_index_response(body["result"])


def load_off_chain(fixtures_path: str) -> list[dict]:
    """Load expected snapshots from an oracle JSON fixture file."""
    with open(fixtures_path, "r") as fh:
        data = json.load(fh)
    if isinstance(data, list):
        return data
    # Support single-object fixtures wrapped in a list
    return [data]


# ── Entrypoint ───────────────────────────────────────────────────────────────

def main() -> None:
    """Poll on-chain FCI, compare against fixture snapshots, print report."""
    rpc_url = os.environ.get("SEPOLIA_RPC_URL", "")
    adapter_address = os.environ.get("ADAPTER_ADDRESS", "")
    fixtures_path = os.environ.get(
        "FIXTURES_PATH",
        "research/data/fixtures/fci_v3_weth_usdc.json",
    )

    if not rpc_url:
        print("ERROR: SEPOLIA_RPC_URL not set", file=sys.stderr)
        sys.exit(1)
    if not adapter_address:
        print("ERROR: ADAPTER_ADDRESS not set", file=sys.stderr)
        sys.exit(1)

    snapshots = load_off_chain(fixtures_path)
    on_index, on_theta, on_pos = poll_on_chain(rpc_url, adapter_address)

    epsilon = float(os.environ.get("EPSILON", "0.01"))
    passed_count = 0

    print("Pool: ETH/USDC 500bps")
    print(f"Window: block {snapshots[0].get('block', '?')} \u2192 "
          f"{snapshots[-1].get('block', '?')}")
    print()

    for snap in snapshots:
        off_index = int(snap.get("indexA", snap.get("index", 0)))
        off_pos = int(snap.get("posCount", snap.get("pos_count", 0)))
        off_theta = int(snap.get("thetaSum", snap.get("theta_sum", 0)))

        result = check_convergence(
            on_chain_index=on_index,
            off_chain_index=off_index,
            epsilon=epsilon,
        )
        if result.passed:
            passed_count += 1

        verdict = "PASS" if result.passed else "FAIL"
        print(f"  On-chain  indexA: {on_index:#x}  "
              f"posCount: {on_pos}  thetaSum: {on_theta:#x}")
        print(f"  Off-chain indexA: {off_index:#x}  "
              f"posCount: {off_pos}  thetaSum: {off_theta:#x}")
        print(f"  Drift: {result.drift:.2%}  {verdict}")
        print()

    total = len(snapshots)
    print(f"  Overall: {passed_count}/{total} snapshots converged "
          f"within \u03b5={epsilon:.0%}")

    if passed_count < total:
        sys.exit(1)


if __name__ == "__main__":
    main()
