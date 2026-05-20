#!/bin/bash
set -euo pipefail

# Queues a CuttingBoardManager → V1_1 upgrade into the Safe multisig UI.
# The BatchScript encodes upgradeToAndCall and sends it to the Safe transaction
# service so signers can review and confirm via app.safe.global.
#
# Requires in .env:
#   PRIVATE_KEY  — EOA private key of a Safe proposer (does not need to be a signer)

source .env

# ── addresses ─────────────────────────────────────────────────────────────────
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"            # Infrared governance Safe
PROXY="0xFDfC1F27909C0983aF7A5509aa44333e0c00C49c"           # CuttingBoardManager proxy
IMPLEMENTATION="0x0000000000000000000000000000000000000000"  # TODO: fill in after deploy
# ──────────────────────────────────────────────────────────────────────────────

RPC_URL="https://rpc.berachain.com"

echo "Safe:           $SAFE"
echo "Proxy:          $PROXY"
echo "Implementation: $IMPLEMENTATION"
echo ""
read -p "Queue upgrade to Safe? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

forge script \
    script/upgrades/cutting-board-manager/v1.1/UpgradeCuttingBoardManagerV1_1.s.sol:UpgradeCuttingBoardManagerV1_1 \
    --sig "run(address,address,address)" "$SAFE" "$PROXY" "$IMPLEMENTATION" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --ffi \
    -vvvv
