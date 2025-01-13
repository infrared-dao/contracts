set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
NAME="Wrapped Infrared Vault IBGT"
SYMBOL="wIBGT"
STAKING_TOKEN="0x7D6e08fe0d56A7e8f9762E9e65daaC491A0B475b" # ibgt
MULTISIG_ADDRESS="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"

INFRARED="0xEb68CBA7A04a4967958FadFfB485e89fE8C5f219"


# Cartio RPC URL
RPC_URL="https://amberdew-eth-cartio.berachain.com"

VERIFYER_URL='https://api.routescan.io/v2/network/testnet/evm/80000/etherscan'

forge script script/WrappedVaultDeployer.s.sol:WrappedVaultDeployer \
    --sig "run(address,address,address,string,string)" $MULTISIG_ADDRESS $INFRARED $STAKING_TOKEN "$NAME" "$SYMBOL" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $VERIFYER_URL \
    --etherscan-api-key "verifyContract" \
    --broadcast 
