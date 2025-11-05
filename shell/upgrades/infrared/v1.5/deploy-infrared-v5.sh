set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# RPC URL
RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.5/DeployInfraredV1_5.s.sol:DeployInfraredV1_5 \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv
    # --verifier-url $VERIFYER \
    # --etherscan-api-key $BERASCAN_API_KEY -vvvv
    