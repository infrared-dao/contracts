#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Define the list of staking assets
STAKING_ASSETS=(
    "0x7f2B60fDff1494A0E3e060532c9980d7fad0404B"
    # Add more staking token addresses here (space separated list)
)

# Change these to correct params
MULTISIG_ADDRESS="0x03915AaeF5fEb997E130fdeF03f4946A9d3d79d2"
INFRARED="0x2fd43a16F5F5F0D8BFBEf59a8cE11640939F1f9C"
RPC_URL="http://35.203.86.197:8545/"
VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan'

# Iterate through staking assets and deploy vaults
for STAKING_TOKEN in "${STAKING_ASSETS[@]}"; do
    # Fetch the token name using cast
    TOKEN_NAME=$(cast call $STAKING_TOKEN "name()(string)" --rpc-url $RPC_URL)
    TOKEN_SYMBOL=$(cast call $STAKING_TOKEN "symbol()(string)" --rpc-url $RPC_URL)

    # remove quotes
    TOKEN_NAME=$(echo $TOKEN_NAME | tr -d '"')
    TOKEN_SYMBOL=$(echo $TOKEN_SYMBOL | tr -d '"')
    
    # Construct the vault's NAME and SYMBOL
    NAME="Wrapped Infrared Vault $TOKEN_NAME"
    SYMBOL="wiv-$TOKEN_SYMBOL"
    
    echo "Deploying vault for $TOKEN_NAME..."
    echo "NAME: $NAME, SYMBOL: $SYMBOL"

    # Run the deployment script
    FOUNDRY_PROFILE=production forge script script/WrappedVaultDeployer.s.sol:WrappedVaultDeployer \
        --sig "run(address,address,address,string,string)" $MULTISIG_ADDRESS $INFRARED $STAKING_TOKEN "$NAME" "$SYMBOL" \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --verifier-url $VERIFYER_URL \
        --etherscan-api-key $ETHERSCAN_API_KEY \
        --broadcast
done

echo "Deployment complete."

# check if verified
# if not run the below with the info filled in
# forge verify-contract <AboveDeployAddress> src/core/WrappedVault.sol:WrappedVault --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,string,string)" 0x03915AaeF5fEb997E130fdeF03f4946A9d3d79d2 0x2fd43a16F5F5F0D8BFBEf59a8cE11640939F1f9C $STAKING_TOKEN "$NAME" "$SYMBOL") --watch