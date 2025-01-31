#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Define the list of staking assets
STAKING_ASSETS=(
    "0xA4d6d4e667efFE07f0C6777399721Ddd03f04630"
    # "0x73D25BF215A7487badC695d7ADa30f1Ad509D642"
    "0x7f2B60fDff1494A0E3e060532c9980d7fad0404B"
    "0x90C65009504C8DDA1A78cA24fe5D80264A568aab"
    # "0xA32E098b42562654cdf4F17f1ea9F32781A45dA9"
    "0x474F32Eb1754827C531C16330Db07531e901BcBe"
    "0x341AB1EF96517E88F276c8455eF5e6a6e1Fb2958"
    "0xE6dE202a0d14af12b298b6c07CB8653d1c2E12dD"
    "0x6b644e825E0E0154b2F6B9fF0CEC0DA527f63269"
    "0x3000C6BF0AAEb813e252B584c4D9a82f99e7a71D"
    "0x5185D57c303f5cB2CF1cFC1F251264f65BA7D534"
    "0xA73e05d03E612c41a0b350fCA180c5D5a8Bc884b"
    "0xbE939e5aFB703E4Ff25058A105CA0bf078edEe21"
    "0xA8Cb3818Fa799018bc862ADE08F8a37e08BA1062"
    "0xB089044EC7DC233736F98B1a410d3B9e559A7932"
    "0x9875ec2a91aE0445a3D365C242987D3f7b81C2A4"
    "0x426f6E1a8a8e43A64CcAF651790fA81d077a1017"
    "0xd6eb8ae479EdF452d264493708c85AA798CCCdFd"
    "0x16DC2EAb270C74EBc2B963d1461b54Da98fA113e"
    "0x529798C3aC58C14cF0f828af94ABc59D5deDb96e"
    "0x0d1A3CE611CE10b72d4A14DaE2A4443855B6DFc3"
    "0xD628b5aBD6829896134FfdAeeA8393dc531A1Efd"
    # "0x107CfC6Ab0776D8C9d452f44A24853Bec87ddBc5"
    "0x444868B6e8079ac2c55eea115250f92C2b2c4D14"
    "0xF2d2d55Daf93b0660297eaA10969eBe90ead5CE8"
    "0xAa97D791Afc02AF30cf0B046172bb05b3c306517"
    "0x29cF6e8eCeFb8d3c9dd2b727C1b7d1df1a754F6f"
    "0xf7b5127B510E568fdC39e6Bb54e2081BFaD489AF"
    # "0x3124AEd0a53BDFD29590001140309ADC3b258d8D"
    "0x538882fC289F33E87E4b24142CcFB4B8EFba7678"
    "0xC6AdB1e9cb781b9573B2cB83809E318D9619BC74"
    "0x054AaE186C130006c65A634e0d63EFE3132034FA"
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
    NAME="Wrapped Infrared Vault ${TOKEN_NAME}"
    SYMBOL="wiv-${TOKEN_SYMBOL}"
    
    echo "Deploying vault for ${TOKEN_NAME}..."
    echo "NAME: $NAME, SYMBOL: $SYMBOL"

    # Run the deployment script
    forge script script/WrappedVaultDeployer.s.sol:WrappedVaultDeployer \
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