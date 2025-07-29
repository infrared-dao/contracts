#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
RPC_URL="https://rpc.berachain.com"

# Run the deployment script
FOUNDRY_PROFILE=production forge script script/DeployBatchClaimer.s.sol:DeployBatchClaimer \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify \
    --broadcast
