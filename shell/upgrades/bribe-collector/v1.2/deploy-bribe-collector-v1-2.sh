set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production forge script script/DeployBribeCollectorV1_2.s.sol:DeployBribeCollectorV1_2 \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $VERIFYER \
    --etherscan-api-key $BERASCAN_API_KEY -vvvv
    