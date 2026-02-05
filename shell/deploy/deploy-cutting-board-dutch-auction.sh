#!/bin/bash
set -euo pipefail

# Load environment variables (expects PRIVATE_KEY in .env)
source .env

# ============================================
# DEPLOYMENT CONFIGURATION
# ============================================

# Network RPC URL
RPC_URL="https://rpc.berachain.com"

# Payment token (IR on mainnet)
export PAYMENT_TOKEN="0xa1B644AEC990Ad6023811cED36E6A2d6D128C7C9"

# Treasury address (Infrared multisig)
export TREASURY_ADDRESS="0xDEeeBE8AF45aC8c5f2a46Efffd3c54d0b19ba23b"

# Owner address (governance multisig)
export OWNER_ADDRESS="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"

# Keeper address (can be same as owner initially, or dedicated keeper)
export KEEPER_ADDRESS="0xbA41911BCAa083287257c5cEba9150f33DAEE849"

export CHEF_ADDRESS=0xdf960E8F3F19C481dDE769edEDD439ea1a63426a
export INFRARED_ADDRESS=0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126

# Auction parameters
export AUCTION_DURATION=$((36 * 3600))  # 36 hours in seconds
export ALLOCATION_DURATION=$((14 * 24 * 3600)) # 14 days in seconds
export PROPOSAL_VALIDITY_DURATION=$((24 * 3600)) # 1 day in seconds
export MAX_AUCTIONS=40000000                   # Number of auctions in the series

# Price dynamics
export STARTING_PRICE_MULTIPLIER=$((2 * 10**18))  # 2e18 = 2x previous closing price
export BASE_PRICE_DIVISOR=$((2 * 10**18))         # 2e18 = 0.5x previous closing price
export MINIMUM_PRICE="200000000000000000000000"            # 400k tokens minimum floor price

export NFT_BASE_URI="https://ipfs.io/ipfs/bafkreidb4xyuymie2j3l7bbclgzfx4oeygphlykw7t2azrtkukfgrdrzdy"

# ============================================
# DEPLOYMENT
# ============================================

echo "=========================================="
echo "Deploying CuttingBoardDutchAuction"
echo "=========================================="
echo "Network: Berachain Mainnet"
echo "Payment Token: $PAYMENT_TOKEN"
echo "Treasury: $TREASURY_ADDRESS"
echo "Owner: $OWNER_ADDRESS"
echo "Keeper: $KEEPER_ADDRESS"
echo ""
echo "Auction Duration: $((AUCTION_DURATION / 3600)) hours"
echo "Max Auctions: $MAX_AUCTIONS"
echo "Starting Price Multiplier: $((STARTING_PRICE_MULTIPLIER / 10**18))x"
echo "Base Price Divisor: $((BASE_PRICE_DIVISOR / 10**18))x"
echo "Minimum Price: $MINIMUM_PRICE tokens"

echo "Dry run deploy"

forge clean

FOUNDRY_PROFILE=production forge build

# FOUNDRY_PROFILE=production forge script script/deploy/DeployCuttingBoardAuction.s.sol:DeployCuttingBoardAuction \
#     --fork-url $RPC_URL \
#     -vvvv

echo ""
read -p "Proceed with deployment? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Deployment cancelled"
    exit 1
fi

# Run the deployment script with production profile
FOUNDRY_PROFILE=production forge script script/deploy/DeployCuttingBoardAuction.s.sol:DeployCuttingBoardAuction \
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
echo "1. Set initial price with: setInitialPrice(uint256)"
echo "2. Whitelist reward vaults with: setVaultWhitelist(address, true)"
echo "3. Keeper can start first auction with: startNextAuction()"
