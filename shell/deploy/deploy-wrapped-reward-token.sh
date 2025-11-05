set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# RPC URL
RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production forge script script/deploy/DeployWrappedRewardToken.s.sol:DeployWrappedRewardToken \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv 
    