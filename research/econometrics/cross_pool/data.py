"""Selected pools and collected data for cross-pool concentration analysis.

Pool selection: V3 subgraph top pools by TVL (volume > $1M), 2-4-4 stratification.
A_T computed via Dune query 6784588 (90-day window, 2026-03-05).
Total Dune cost: ~3 credits.
"""
from __future__ import annotations

import json as _json
from pathlib import Path as _Path
from typing import Final

from econometrics.cross_pool.types import PoolConcentration, PoolInfo

_FROZEN = _Path(__file__).resolve().parent.parent.parent / "data" / "frozen"

def _load_frozen(name: str):
    return _json.loads((_FROZEN / name).read_text())

# ── Selected pools: loaded from canonical frozen JSON ──
_pools_data = _load_frozen("selected_pools.json")
SELECTED_POOLS: Final[list[PoolInfo]] = [
    PoolInfo(
        address=p["address"], token0_symbol=p["token0_symbol"],
        token1_symbol=p["token1_symbol"], fee_tier=p["fee_tier"],
        tvl_usd=p["tvl_usd"], volume_usd_24h=p["volume_usd_24h"],
        pair_category=p["pair_category"]
    )
    for p in _pools_data["data"]
]

# ── A_T results from Dune query 6784588 (90-day window) ──
# Computed in SQL: A_T = sqrt(sum(theta_k * fee_share_k^2))
POOL_CONCENTRATIONS: Final[list[PoolConcentration]] = [
    # stable/stable
    PoolConcentration(SELECTED_POOLS[0], a_t=0.000620, a_t_null=0.002347, delta_plus=0.0, n_positions=3267, n_removals=3267, window_days=90),
    PoolConcentration(SELECTED_POOLS[1], a_t=0.000085, a_t_null=0.007143, delta_plus=0.0, n_positions=198, n_removals=198, window_days=90),
    # stable/token
    PoolConcentration(SELECTED_POOLS[2], a_t=0.004155, a_t_null=0.003326, delta_plus=0.000830, n_positions=6747, n_removals=6748, window_days=90),
    PoolConcentration(SELECTED_POOLS[3], a_t=0.002084, a_t_null=0.007999, delta_plus=0.0, n_positions=2788, n_removals=2788, window_days=90),
    PoolConcentration(SELECTED_POOLS[4], a_t=0.000654, a_t_null=0.000916, delta_plus=0.0, n_positions=13798, n_removals=13798, window_days=90),
    PoolConcentration(SELECTED_POOLS[5], a_t=0.039633, a_t_null=0.005472, delta_plus=0.034161, n_positions=1563, n_removals=1563, window_days=90),
    # token/token
    PoolConcentration(SELECTED_POOLS[6], a_t=0.012085, a_t_null=0.007583, delta_plus=0.004502, n_positions=1204, n_removals=1204, window_days=90),
    PoolConcentration(SELECTED_POOLS[7], a_t=0.003166, a_t_null=0.006512, delta_plus=0.0, n_positions=1380, n_removals=1380, window_days=90),
    PoolConcentration(SELECTED_POOLS[8], a_t=0.004350, a_t_null=0.005888, delta_plus=0.0, n_positions=1342, n_removals=1342, window_days=90),
    PoolConcentration(SELECTED_POOLS[9], a_t=0.042434, a_t_null=0.030027, delta_plus=0.012407, n_positions=300, n_removals=300, window_days=90),
]
