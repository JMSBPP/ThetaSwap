"""Generate baseline SHA-256 hashes for all hardcoded datasets."""
import hashlib
import json
import sys
sys.path.insert(0, "research")

from econometrics.data import RAW_POSITIONS, DAILY_AT_MAP, DAILY_AT_NULL_MAP, IL_MAP
from econometrics.cross_pool.data import SELECTED_POOLS, POOL_CONCENTRATIONS
from econometrics.per_position_data import PER_POSITION_DATA

def canon(obj) -> str:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"))

def sha(obj) -> str:
    return hashlib.sha256(canon(obj).encode()).hexdigest()

datasets = {
    "il_proxy": {k: v for k, v in IL_MAP.items()},
    "daily_at": {"real": {k: v for k, v in DAILY_AT_MAP.items()},
                  "null": {k: v for k, v in DAILY_AT_NULL_MAP.items()}},
    "positions": [[d, bl, at] for d, bl, at in RAW_POSITIONS],
    "selected_pools": [
        {"address": p.address, "token0_symbol": p.token0_symbol,
         "token1_symbol": p.token1_symbol, "fee_tier": p.fee_tier,
         "tvl_usd": p.tvl_usd, "volume_usd_24h": p.volume_usd_24h,
         "pair_category": p.pair_category}
        for p in SELECTED_POOLS
    ],
    "pool_concentrations": [
        {"pool_address": pc.pool.address, "a_t": pc.a_t, "a_t_null": pc.a_t_null,
         "delta_plus": pc.delta_plus, "n_positions": pc.n_positions,
         "n_removals": pc.n_removals, "window_days": pc.window_days}
        for pc in POOL_CONCENTRATIONS
    ],
    "per_position_fees": [[d, bl, xs, tid] for d, bl, xs, tid in PER_POSITION_DATA],
}

hashes = {name: sha(data) for name, data in datasets.items()}
with open("tmp/baseline-hashes.json", "w") as f:
    json.dump(hashes, f, indent=2)

print("Baseline hashes:")
for name, h in hashes.items():
    print(f"  {name}: {h[:16]}...")
