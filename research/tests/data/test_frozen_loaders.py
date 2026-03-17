"""Tests that frozen JSON loaders produce byte-identical data to hardcoded values."""
import hashlib
import json
from pathlib import Path

FROZEN_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "frozen"
BASELINE = json.loads(
    (Path(__file__).resolve().parent.parent.parent.parent / "tmp" / "baseline-hashes.json").read_text()
)

def _sha(obj) -> str:
    return hashlib.sha256(
        json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()

def test_il_proxy_hash_matches_baseline():
    frozen = json.loads((FROZEN_DIR / "il_proxy.json").read_text())
    assert _sha(frozen["data"]) == BASELINE["il_proxy"]
    assert frozen["metadata"]["source"] == "derived"
    assert frozen["metadata"]["row_count"] == 41

def test_il_proxy_loader_matches_baseline():
    from econometrics.data import IL_MAP
    assert _sha({k: v for k, v in IL_MAP.items()}) == BASELINE["il_proxy"]

def test_daily_at_hash_matches_baseline():
    frozen = json.loads((FROZEN_DIR / "daily_at.json").read_text())
    assert _sha(frozen["data"]) == BASELINE["daily_at"]
    assert frozen["metadata"]["source"] == "dune"
    assert frozen["metadata"]["query_id"] == 6783604

def test_daily_at_loader_matches_baseline():
    from econometrics.data import DAILY_AT_MAP, DAILY_AT_NULL_MAP
    combined = {"real": {k: v for k, v in DAILY_AT_MAP.items()},
                "null": {k: v for k, v in DAILY_AT_NULL_MAP.items()}}
    assert _sha(combined) == BASELINE["daily_at"]

def test_positions_hash_matches_baseline():
    frozen = json.loads((FROZEN_DIR / "positions.json").read_text())
    assert _sha(frozen["data"]) == BASELINE["positions"]
    assert frozen["metadata"]["source"] == "frozen_original"
    assert frozen["metadata"]["row_count"] == 600

def test_positions_loader_matches_baseline():
    from econometrics.data import RAW_POSITIONS
    assert _sha([[d, bl, at] for d, bl, at in RAW_POSITIONS]) == BASELINE["positions"]
    assert len(RAW_POSITIONS) == 600
    assert isinstance(RAW_POSITIONS[0], tuple)
    assert isinstance(RAW_POSITIONS[0][0], str)
    assert isinstance(RAW_POSITIONS[0][1], int)
    assert isinstance(RAW_POSITIONS[0][2], float)
