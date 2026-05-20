#!/bin/bash
set -euo pipefail

# Upgrades the CuttingBoardDutchAuction proxy to V1_2 on Bepolia.
# The caller's PRIVATE_KEY must hold GOVERNANCE_ROLE on the proxy.
#
# Requires in .env:
#   PRIVATE_KEY  — EOA private key that is governance on the Bepolia proxy

source .env

# ── addresses ────────────────────────────────────────────────────────────────
# Proxy deployed by deploy-cutting-board-dutch-auction-bepolia.sh
PROXY="0x0302De7060AaD80f42C72E6463efFa9260C2ffD7"           # Bepolia DutchAuction proxy

# Implementation deployed by deploy-cutting-board-dutch-auction-v1-2-bepolia.sh
IMPLEMENTATION="0x0000000000000000000000000000000000000000"  # TODO: fill in after deploy
# ─────────────────────────────────────────────────────────────────────────────

RPC_URL="https://bepolia.rpc.berachain.com"

forge script \
    script/upgrades/cutting-board-dutch-auction/v1.2/UpgradeCuttingBoardDutchAuctionV1_2Testnet.s.sol:UpgradeCuttingBoardDutchAuctionV1_2Testnet \
    --sig "run(address,address)" "$PROXY" "$IMPLEMENTATION" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvvv
