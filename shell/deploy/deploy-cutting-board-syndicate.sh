#!/bin/bash
set -euo pipefail

# Load environment variables (expects PRIVATE_KEY in .env)
source .env

# ============================================
# DEPLOYMENT CONFIGURATION
# ============================================

# Network RPC URL
RPC_URL="https://rpc.berachain.com"

# Existing contract addresses (from CuttingBoardDutchAuction deployment)
export DUTCH_AUCTION_ADDRESS="0x50Ab64a24268b79dd10Dab18c59AFeF256E6DC84"
export CONTROL_MANAGER_ADDRESS="0xFDfC1F27909C0983aF7A5509aa44333e0c00C49c"
export CONTROL_NFT_ADDRESS="0xEC09569A9A186027EcD1C951F5F80F9a43184fb1"
export CHEF_ADDRESS=0xdf960E8F3F19C481dDE769edEDD439ea1a63426a

# Owner address (governance multisig)
export OWNER_ADDRESS="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"

# Keeper address
export KEEPER_ADDRESS="0xbA41911BCAa083287257c5cEba9150f33DAEE849"

# Syndicate parameters
export MIN_SLOT_WEIGHT=500  # 5% = 500 bps (0 defaults to 100)

# Optional: SlotNFT metadata URI
export SLOT_NFT_BASE_URI=""

# ============================================
# DEPLOYMENT
# ============================================

echo "=========================================="
echo "Deploying CuttingBoardSyndicate + SlotNFT"
echo "=========================================="
echo "Network: Berachain Mainnet"
echo "Dutch Auction: $DUTCH_AUCTION_ADDRESS"
echo "Control Manager: $CONTROL_MANAGER_ADDRESS"
echo "Control NFT: $CONTROL_NFT_ADDRESS"
echo "Owner: $OWNER_ADDRESS"
echo "Keeper: $KEEPER_ADDRESS"
echo "Min Slot Weight: $MIN_SLOT_WEIGHT bps"
echo ""

echo "Dry run deploy"

forge clean

FOUNDRY_PROFILE=production forge build

# Dry run (uncomment to test against a fork)
# FOUNDRY_PROFILE=production forge script script/deploy/DeployCuttingBoardSyndicate.s.sol:DeployCuttingBoardSyndicate \
#     --fork-url $RPC_URL -vvvv

echo ""
read -p "Proceed with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Deployment cancelled"
    exit 1
fi

# Run the deployment script with production profile
FOUNDRY_PROFILE=production forge script script/deploy/DeployCuttingBoardSyndicate.s.sol:DeployCuttingBoardSyndicate \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Verify both contracts on block explorer"
echo "2. Configure syndicate parameters if needed"
echo ""
