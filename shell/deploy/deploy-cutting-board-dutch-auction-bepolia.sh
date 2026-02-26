#!/bin/bash
set -euo pipefail

# Load environment variables (expects PRIVATE_KEY in .env)
source .env

# ============================================
# DEPLOYMENT CONFIGURATION - BEPOLIA TESTNET
# ============================================

# Network RPC URL
RPC_URL="https://bepolia.rpc.berachain.com"

# Payment token (testnet IR)
export PAYMENT_TOKEN="0x58C3378b89D84f966034f57BCc331323b3ca1B28"

# Treasury address (can use deployer address for testing)
DEPLOYER_ADDRESS=$(cast wallet address --private-key $PRIVATE_KEY)
export TREASURY_ADDRESS="${TREASURY_ADDRESS:-$DEPLOYER_ADDRESS}"

# Owner address (can use deployer address for testing)
export OWNER_ADDRESS="${OWNER_ADDRESS:-$DEPLOYER_ADDRESS}"

# Keeper address (can use deployer address for testing)
export KEEPER_ADDRESS="${KEEPER_ADDRESS:-$DEPLOYER_ADDRESS}"

export CHEF_ADDRESS=0xdf960E8F3F19C481dDE769edEDD439ea1a63426a
export INFRARED_ADDRESS=0xb4fe1c9a7068586f377eCaD40632347be2372E6C

# Auction parameters (shorter for testing)
export AUCTION_DURATION=$((4 * 3600))  # 12 hours in seconds (shorter for testing)
export ALLOCATION_DURATION=$((14 * 24 * 3600)) # 14 days in seconds
export PROPOSAL_VALIDITY_DURATION=$((24 * 3600)) # 1 day in seconds
export EMISSIONS_PORTION=500            # 500 bps = 5%
export MAX_AUCTIONS=3000                   # Fewer auctions for testing

# Price dynamics
export STARTING_PRICE_MULTIPLIER=$((2 * 10**18))  # 2e18 = 2x previous closing price
export BASE_PRICE_DIVISOR=$((2 * 10**18))         # 2e18 = 0.5x previous closing price
export MINIMUM_PRICE="10000000000000000000"             # 10 tokens minimum floor price (lower for testing)
echo $MINIMUM_PRICE
# ============================================
# DEPLOYMENT
# ============================================

echo "=========================================="
echo "Deploying CuttingBoardDutchAuction"
echo "=========================================="
echo "Network: Berachain Bepolia Testnet"
echo "Payment Token: $PAYMENT_TOKEN"
echo "Treasury: $TREASURY_ADDRESS"
echo "Owner: $OWNER_ADDRESS"
echo "Keeper: $KEEPER_ADDRESS"
echo ""
echo "Auction Duration: $((AUCTION_DURATION / 3600)) hours"
echo "Emissions Portion: $EMISSIONS_PORTION bps ($((EMISSIONS_PORTION / 100))%)"
echo "Max Auctions: $MAX_AUCTIONS"
echo "Starting Price Multiplier: $((STARTING_PRICE_MULTIPLIER / 10**18))x"
echo "Base Price Divisor: $((BASE_PRICE_DIVISOR / 10**18))x"
echo "Minimum Price: $MINIMUM_PRICE tokens"
echo ""

# forge script script/deploy/DeployCuttingBoardAuction.s.sol:DeployCuttingBoardAuction \
#     --fork-url $RPC_URL \
#     --private-key $PRIVATE_KEY \
#     -vvvv

read -p "Proceed with deployment? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Deployment cancelled"
    exit 1
fi

# Run the deployment script
forge script script/deploy/DeployCuttingBoardAuction.s.sol:DeployCuttingBoardAuction \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE - TESTNET"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Get testnet HONEY from faucet"
echo "2. Set initial price with: setInitialPrice(uint256)"
echo "3. Whitelist test vaults with: setVaultWhitelist(address, true)"
echo "4. Approve HONEY: approve(auctionAddress, amount)"
echo "5. Keeper can start first auction with: startNextAuction()"
echo "6. Test claiming with: claimPortion(auctionId, vault)"
