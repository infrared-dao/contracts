#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Infrared BERA Validator Exit Automation Script
# =============================================================================

# Load env (make sure you have KEYSTORE, PASSWORD in .env)
source .env

# --------------------------- CONFIG ------------------------------------------
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredBERAKeeper.s.sol:InfraredBERAKeeper"

PROOF_SERVER="http://142.132.132.71" # hetzner
PROOF_ENDPOINT="/proofs/combined"

SCRIPT="script/keeper/InfraredBERAKeeper.s.sol:InfraredBERAKeeper"
SIG="registerViaProofs(address,address,string)"

# --------------------------- INPUTS -----------------------------------------
PUBKEY="0x90d64ab2a8ab9b5faace9225d205d47dc0b8155592b354b860134928f7f39f15f54d909dad7897868aba6dc7e7eef6c8"
WITHDRAWOR=0x8c0E122960dc2E97dc0059c07d6901Dce72818E1
IBERA=0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5

# Where to save the proof inside the repo (relative to repo root)
PROOF_REL_PATH="/tests/data/proof_A41_register.json"
# PROOF_ABS_PATH="$(git rev-parse --show-toplevel)/$PROOF_REL_PATH"

# Sender (your hot wallet)
SENDER=0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7

# =============================================================================

echo "=== Infrared Validator Register Automation ==="
echo "Validator pubkey: $PUBKEY"
echo "Proof will be saved to: $PROOF_REL_PATH"
echo

# ------------------- 1. Fetch proof from your API -----------------------------
# echo "[1/4] Requesting combined proof from $PROOF_SERVER..."
# curl -X POST http://localhost:8000/proofs/combined   -H "Content-Type: application/json"   -d '{"identifier": "0x90d64ab2a8ab9b5faace9225d205d47dc0b8155592b354b860134928f7f39f15f54d909dad7897868aba6dc7e7eef6c8"}'

# ------------------- 2. Dry run (simulation) ---------------------------------
echo
echo "[2/4] Running dry-run simulation..."

forge script $SCRIPT \
    --sig "$SIG" "$WITHDRAWOR" "$IBERA" "$PROOF_REL_PATH" \
    --fork-url "$RPC_URL" \
    -vvvv \
    --sender "$SENDER" --unlocked

echo "✓ Dry-run completed successfully"

# ------------------- 3. Ask for confirmation before broadcast ----------------
echo
echo "[3/4] Ready to broadcast the following transactions:"
echo "   • Execute registerViaProofs with proof"
echo
read -p "Do you want to BROADCAST these transactions now? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted by user. You can broadcast later with --yes flag."
    exit 0
fi

# ------------------- 4. Broadcast --------------------------------------------
echo
echo "[4/4] Broadcasting..."

forge script $SCRIPT \
    --sig "$SIG" "$WITHDRAWOR" "$IBERA" "$PROOF_REL_PATH" \
    --rpc-url "$RPC_URL" \
    --keystore "$KEYSTORE" \
    --password "$PASSWORD" \
    --broadcast \
    --sender "$SENDER" \
    -vvvv

echo
echo "All transactions broadcasted!"
echo "Proof file: $PROOF_REL_PATH"
