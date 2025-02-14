set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Cartio RPC URL
RPC_URL="https://rpc.berachain.com"

# VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan'

FOUNDRY_PROFILE=production forge script script/DeployInfraredV1_2.s.sol:DeployInfraredV1_2 \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY -vvvv
    # --verifier-url $VERIFYER_URL \
    # --etherscan-api-key "verifyContract" -vvvv
    