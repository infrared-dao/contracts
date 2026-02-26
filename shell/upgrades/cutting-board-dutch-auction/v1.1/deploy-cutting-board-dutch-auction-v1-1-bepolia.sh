#!/bin/bash
set -euo pipefail

# Deploys the CuttingBoardDutchAuctionV1_1 implementation on Bepolia.
# Note the resulting address — you need it for the upgrade shell.
#
# Requires in .env:
#   PRIVATE_KEY       — EOA private key with ETH for gas
#   BERASCAN_API_KEY  — for contract verification
#   VERIFYER          — verifier URL (e.g. https://api.berascan.com/api)

source .env

RPC_URL="https://bepolia.rpc.berachain.com"

FOUNDRY_PROFILE=production forge script \
    script/upgrades/cutting-board-dutch-auction/v1.1/DeployCuttingBoardDutchAuctionV1_1.s.sol:DeployCuttingBoardDutchAuctionV1_1 \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --verify \
    -vvvv
