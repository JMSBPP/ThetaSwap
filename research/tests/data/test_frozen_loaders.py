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
