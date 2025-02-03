#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Define the list of staking assets
STAKING_ASSETS=(
    "0xf6c6Be0FF6d6F70A04dBE4F1aDE62cB23053Bd95"
    "0xf6b16E73d3b0e2784AAe8C4cd06099BE65d092Bf"
    "0x58FDB6EEbf7df7Ce4137994436fb0e629Bb84b84"
    "0xb73deE52F38539bA854979eab6342A60dD4C8c03"
    "0x12C195768f65F282EA5F1B5C42755FBc910B0D8F"
    "0xE5A2ab5D2fb268E5fF43A5564e44c3309609aFF9"
    "0xD5B6EA3544a51BfdDa7E6926BdF778339801dFe8"
    "0x74E852a4f88bfbEff01275bB95d5ed77f2967d12"
    "0x933b2e6a71edBF11BBA75C5Ad241D246b145E0b0"
    "0x78F87aA41a4C32a619467d5B36e0319F3EAf2DA2"
    "0xbfbEfcfAE7a58C14292B53C2CcD95bF2c5742EB0"
    "0x7CeBCc76A2faecC0aE378b340815fcbb71eC1Fe0"
    "0x63b0EdC427664D4330F72eEc890A86b3F98ce225"
    "0x7fd165B73775884a38AA8f2B384A53A3Ca7400E6"
    "0x03bCcF796cDef61064c4a2EffdD21f1AC8C29E92"
    "0x57161d6272F47cd48BA165646c802f001040C2E0"
    "0x97431F104be73FC0e6fc731cE84486DA05C48871"
    "0xba4d7a7dF1999D6F29DE133872CDDD5Cb46C6694"
    "0xB67D60fc02E0870EdDca24D4fa8eA516c890152b"
    "0x502eED2a3a88Ffd2B49d7f5018C7Ca9965C43e95"
    "0x3879451f4f69F0c2d37CaD45319cFf2E7d29C596"
    "0x43E487126c4F37D1915cF02a90B5C5295AFb1790"
    "0x72768fED7f56CA010974aAB65e1467AC8567902C"
    "0xc64794dc7c550B9A4a8F7cAF68e49F31C0269D90"
    "0x377daaf5043eBDBDf15e79edB143D7e2df2ecF4A"
    "0x069759428dBf32DE4cFa2d107F5205D5BbdCd02F"
    "0x7428f72B70226b6C98DDBe14f80Ea23336528B1a"
    "0x42930C47C681d4C78692aE8A88Eb277e494fDd27"
    "0x7297485557E5488Ff416A8349aF29717dF7AE625"
    "0xbC865D60eCCeC3b412a32f764667291C54C93736"
    "0xA91D046D26b540c875Bc3CC785181A270bC37704"
    "0x1d5224Aff66EbB2Cf46De98f69A5982f650F098c"
    "0xadD169f7E0905fb2e78cDFBee155c975Db0F2cbe"
    "0xEFb340d54D54E1C4E3566878a5D64A3a591e12A3"
    "0xFF619BDaeDF635251c3aF5BFa82bcaf856C95cC3"
    "0xba86cd31c9e142ed833748ab6304e82a48d34b32"
    "0xf8163EaC4c0239a81a7d8BD05B8e14498a5fD880"
    # Add more staking token addresses here (space separated list)
)

# Change these to correct params
MULTISIG_ADDRESS="0x03915AaeF5fEb997E130fdeF03f4946A9d3d79d2"
INFRARED="0xb71b3daea39012fb0f2b14d2a9c86da9292fc126"
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
    FOUNDRY_PROFILE=production forge script script/WrappedVaultDeployer.s.sol:WrappedVaultDeployer \
        --sig "run(address,address,address,string,string)" $MULTISIG_ADDRESS $INFRARED $STAKING_TOKEN "$NAME" "$SYMBOL" \
        --rpc-url $RPC_URL \
        --private-key $PRIVATE_KEY \
        --verifier-url $VERIFYER_URL \
        --etherscan-api-key "verifyContract" \
        --broadcast
done

echo "Deployment complete."

# check if verified
# if not run the below with the info filled in
# forge verify-contract <AboveDeployAddress> src/core/WrappedVault.sol:WrappedVault --verifier-url 'https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan' --etherscan-api-key "verifyContract"  --num-of-optimizations 1  --compiler-version 0.8.26 --constructor-args $(cast abi-encode "constructor(address,address,address,string,string)" 0x03915AaeF5fEb997E130fdeF03f4946A9d3d79d2 0x2fd43a16F5F5F0D8BFBEf59a8cE11640939F1f9C $STAKING_TOKEN "$NAME" "$SYMBOL") --watch
