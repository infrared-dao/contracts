#!/bin/bash
set -euo pipefail

# Upgrades the CuttingBoardManager proxy to V1_1 on Bepolia.
# The caller's PRIVATE_KEY must hold GOVERNANCE_ROLE on the proxy.
#
# Requires in .env:
#   PRIVATE_KEY  — EOA private key that is governance on the Bepolia proxy

source .env

# ── addresses ────────────────────────────────────────────────────────────────
# Proxy deployed by deploy-cutting-board-dutch-auction-bepolia.sh (Manager shares deploy)
PROXY="0x5036221140cD9048f19f08B66E54aba0208d464c"           # Bepolia Manager proxy

# Implementation deployed by deploy-cutting-board-manager-v1-1-bepolia.sh
IMPLEMENTATION="0x0000000000000000000000000000000000000000"  # TODO: fill in after deploy
# ─────────────────────────────────────────────────────────────────────────────

RPC_URL="https://bepolia.rpc.berachain.com"

forge script \
    script/upgrades/cutting-board-manager/v1.1/UpgradeCuttingBoardManagerV1_1Testnet.s.sol:UpgradeCuttingBoardManagerV1_1Testnet \
    --sig "run(address,address)" "$PROXY" "$IMPLEMENTATION" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvvv
