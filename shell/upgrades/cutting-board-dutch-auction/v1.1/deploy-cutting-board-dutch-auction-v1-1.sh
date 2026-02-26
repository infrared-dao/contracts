#!/bin/bash
set -euo pipefail

# Deploys the CuttingBoardDutchAuctionV1_1 implementation on mainnet.
# Note the resulting address — you need it for the upgrade shell.
#
# Requires in .env:
#   PRIVATE_KEY  — EOA private key with ETH for gas

source .env

RPC_URL="https://rpc.berachain.com"

forge clean
FOUNDRY_PROFILE=production forge build

echo ""
read -p "Deploy CuttingBoardDutchAuctionV1_1 implementation to mainnet? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

FOUNDRY_PROFILE=production forge script \
    script/upgrades/cutting-board-dutch-auction/v1.1/DeployCuttingBoardDutchAuctionV1_1.s.sol:DeployCuttingBoardDutchAuctionV1_1 \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    --verify \
    -vvvv
