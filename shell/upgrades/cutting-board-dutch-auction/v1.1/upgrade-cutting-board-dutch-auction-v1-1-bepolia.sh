#!/bin/bash
set -euo pipefail

# Upgrades the CuttingBoardDutchAuction proxy to V1_1 on Bepolia.
# The caller's PRIVATE_KEY must hold GOVERNANCE_ROLE on the proxy.
#
# Requires in .env:
#   PRIVATE_KEY  — EOA private key that is governance on the Bepolia proxy

source .env

# ── addresses ────────────────────────────────────────────────────────────────
# Proxy deployed by deploy-cutting-board-dutch-auction-bepolia.sh
PROXY="0x0302De7060AaD80f42C72E6463efFa9260C2ffD7"           # TODO: fill in

# Implementation deployed by deploy-cutting-board-dutch-auction-v1-1-bepolia.sh
IMPLEMENTATION="0x06C6D9bEf203C409D88bdf36E8d135C9E1870fD7"  # TODO: fill in
# ─────────────────────────────────────────────────────────────────────────────

RPC_URL="https://bepolia.rpc.berachain.com"

forge script \
    script/upgrades/cutting-board-dutch-auction/v1.1/UpgradeCuttingBoardDutchAuctionV1_1Testnet.s.sol:UpgradeCuttingBoardDutchAuctionV1_1Testnet \
    --sig "run(address,address)" "$PROXY" "$IMPLEMENTATION" \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    -vvvv
