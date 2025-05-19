set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# RPC URL
RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production forge script script/DeployInfraredV1_3.s.sol:DeployInfraredV1_3 \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $VERIFYER \
    --etherscan-api-key $BERASCAN_API_KEY -vvvv
    