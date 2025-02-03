#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Define the list of staking assets
WRAPPED_VAULTS=(
    "0x47590f8c83bb99ff9C9d6640F007722A79f0Ab02"
    "0xFe7A781914525e7e7c93b30C213FBfcdE1C5F575"
    "0xC6B6B099CfbCBC3d23ea9Abfe4DA500134479a29"
    "0xa63fF996cc93bD4E0623F5038ad31D1146aE4f88"
    "0x718874A9402f8E5802607D4D1Cc008274F0BD3D4"
    "0x04edCC9715445dd38f9fb327af8740BdFb81b739"
    "0x58b61ed5c1657e78fFc7E574e8AC42c6f20ebE1E"
    "0xA2b10d1eE0C0F715eF0694E25984d01Ac8bf83D4"
    "0x7f6ed59799d4cFAc23d20B623974e9Fca287da17"
    "0x79A27A5B2A84B60E2869Dd09c46d537B1a6f4EF8"
    "0xCC0C3F6c8C7a9a7c7788D85Ff720830f8aF6d05c"
    "0x9F898E9c5863A13f68A714044D380E9ffFf7B732"
    "0xe193336621B91D9034a7668fD5fE0065AD84f34f"
    "0x6e0D09B502c6e561B287Cd4e66C8eF879c86E20D"
    "0x03c2ef90eC1F5deAb5A16aCCFb49C42ac602Ba65"
    "0xb065F887f23D3707386b3fdfecB252E3C50F5088"
    "0xbc44617088aeaafAcdEb6dE68CFa287fB2CDa130"
    "0x2415FEE8Af7c121e17Ae1B78E0891a8C6112CF8f"
    "0x1eCe52A596C2cBEf7b71Fa8FA8FC738aA7Ad441f"
    "0xf4c35f3A334cA73a229D9d416924f51675240796"
    "0xb59aa6e935C66eea5dEDc0EB385CEB62fbE85757"
    "0xA3a376E370666d0C3e10A5b1067095F2F080f26f"
    "0x81ba24b92B162ba56c622b4b80E4CE26426F490A"
    "0x2E113998f4561Cc15543C380b0A92C60657aE031"
    "0xD76707FFB9FEb81eDA0D6d0EA56d4Eb0325d5673"
    "0x9433cCf93aC084f7191b78d7BD0e7D64Ed344e27"
    "0xD10759bD1Ebd69A4e0873DC3c08c43cfF1f166F4"
    "0x3904AAa585d846096FcDB38ef516C3EBace1ab84"
    "0xbf19612f6eF35Fe411801509e4c284647213f5FE"
    "0x7EF1f9F4e6e2F8f112b953f3b0A71ED1311F4730"
    "0xF3A956b2C29F5c1216A72C88259db9e66E1F3AA1"
    "0xbcD6819A00DF6e7f7E6D5e073fF00A91bc876a9d"
    "0x04bD6ED6408cB573419Fd763e3B7CeD57dE69bd5"
    "0x7e312939980B2842B524D3418Aa9b7498054e39a"
    "0xbdc6D8481Ba06fA7BB043AB0fb74BAE9e774BF12"
    "0x57684b647D4Cc6b151E7476355fcFdc174da7ECE"
    "0xb38b0D08965654f11377c0C90F2338D63926C9B9"
)

# Change these to correct params
MULTISIG_ADDRESS="0x03915AaeF5fEb997E130fdeF03f4946A9d3d79d2"
INFRARED="0xb71b3daea39012fb0f2b14d2a9c86da9292fc126"
RPC_URL="http://35.203.86.197:8545/"
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
