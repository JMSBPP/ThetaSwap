#!/usr/bin/env bash
# V3 Reactive FCI V2 Integration Test — shell orchestrator.
# Deploys everything, plays 2-LP scenario, waits for callbacks, verifies deltaPlus > 0.
#
# Usage: ./scripts/run-v3-integration.sh
#
# Prerequisites:
#   - .env with MNEMONIC, ALCHEMY_API_KEY, REACTIVE_RPC_URL
#   - Deployer funded: Sepolia (~0.5 ETH) + Lasna (~15 lREACT)
#   - forge build must have run (cache populated)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

source .env 2>/dev/null || true

SEPOLIA_RPC="https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
LASNA_RPC="${REACTIVE_RPC_URL:?REACTIVE_RPC_URL not set}"
TEST_FILE="test/fee-concentration-index-v2/protocols/uniswapV3/UniswapV3FeeConcentrationIndex.integration.t.sol"
CONTRACT="UniswapV3FCI_IntegrationScript"
STATE_FILE="broadcast/v3-integration-state.json"
REACTIVE_FILE="broadcast/reactive-addr.txt"
V3_POOL="${V3_POOL:-0xF66da9dd005192ee584a253b024070c9A1A1F4FA}"

DEPLOYER_PK=$(cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-derivation-path "m/44'/60'/0'/0/0" 2>/dev/null)

# ── Phase 1: Deploy Sepolia ──
echo "=== Phase 1: Deploy FCI V2 + Facet + Callback on Sepolia ==="
forge script "${TEST_FILE}:${CONTRACT}" \
    --sig "deploy()" \
    --broadcast --slow \
    --rpc-url "$SEPOLIA_RPC" \
    -vv

CALLBACK=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['callback'])")
echo "Callback: $CALLBACK"

# ── Phase 2: Deploy Reactive on Lasna ──
echo ""
echo "=== Phase 2: Deploy Reactive on Lasna ==="
./scripts/deploy-reactive.sh "$LASNA_RPC" "$DEPLOYER_PK" "$CALLBACK" "$V3_POOL" "$REACTIVE_FILE"
REACTIVE=$(cat "$REACTIVE_FILE")
echo "Reactive: $REACTIVE"

echo "Waiting 10s for subscriptions to activate..."
sleep 10

# ── Phase 3: Mint + Swap ──
echo ""
echo "=== Phase 3: Mint 2 LPs (1:2) + Swap ==="
forge script "${TEST_FILE}:${CONTRACT}" \
    --sig "mint()" \
    --broadcast --slow \
    --rpc-url "$SEPOLIA_RPC" \
    -vv

echo ""
echo "Waiting 90s for mint + swap callbacks..."
sleep 90

# ── Phase 4: Burn ──
echo ""
echo "=== Phase 4: Burn both LPs ==="
forge script "${TEST_FILE}:${CONTRACT}" \
    --sig "burn()" \
    --broadcast --slow \
    --rpc-url "$SEPOLIA_RPC" \
    -vv

echo ""
echo "Waiting 90s for burn callbacks..."
sleep 90

# ── Phase 5: Verify ──
echo ""
echo "=== Phase 5: Verify ==="
forge script "${TEST_FILE}:${CONTRACT}" \
    --sig "verify()" \
    --rpc-url "$SEPOLIA_RPC" \
    -vv

echo ""
echo "=== DONE ==="
