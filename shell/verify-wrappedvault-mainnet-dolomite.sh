#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Define the list of staking assets
WRAPPED_VAULTS=(
    "0xb13A7D1361bd6f6734078654047daAE210f2d4D4"
    "0x01b775b353176bb1b9075C5d344c2B689285282a"
    "0x7de65E4fcc6a0b411B90a24CC33741AB3CD00262"
    "0x778e9294Af38DFc8B92e8969953eB559b47e896E"
)

# Change these to correct params
MULTISIG_ADDRESS="0x03915AaeF5fEb997E130fdeF03f4946A9d3d79d2"
INFRARED="0xb71b3daea39012fb0f2b14d2a9c86da9292fc126"
RPC_URL="https://rpc.berachain.com"
VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan'

# Iterate through staking assets and deploy vaults
for WRAPPED_VAULT in "${WRAPPED_VAULTS[@]}"; do
    
    STAKING_TOKEN=$(cast call $WRAPPED_VAULT "asset()(address)" --rpc-url $RPC_URL)
    INFRA_VAULT=$(cast call $WRAPPED_VAULT "iVault()(address)" --rpc-url $RPC_URL)
    TOKEN_NAME=$(cast call $WRAPPED_VAULT "name()(string)" --rpc-url $RPC_URL)
    TOKEN_SYMBOL=$(cast call $WRAPPED_VAULT "symbol()(string)" --rpc-url $RPC_URL)

    # remove quotes
    TOKEN_NAME=$(echo $TOKEN_NAME | tr -d '"')
    TOKEN_SYMBOL=$(echo $TOKEN_SYMBOL | tr -d '"')

    echo "NAME: $TOKEN_NAME, SYMBOL: $TOKEN_SYMBOL, STAKING_TOKEN: $STAKING_TOKEN, INFRA_VAULT: $INFRA_VAULT"

    # Run the verify for wrapped vault
    forge verify-contract $WRAPPED_VAULT src/core/WrappedVault.sol:WrappedVault --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,string,string)" $MULTISIG_ADDRESS $INFRARED $STAKING_TOKEN "$TOKEN_NAME" "$TOKEN_SYMBOL")

    sleep .5

    # run verify for infrared vault
    forge verify-contract $INFRA_VAULT src/core/InfraredVault.sol:InfraredVault --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 200  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,uint256)" $STAKING_TOKEN 86400)

    sleep .5
done

echo "Verify complete."
