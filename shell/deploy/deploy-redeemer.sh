#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

# Run the deployment script
FOUNDRY_PROFILE=production forge script script/DeployRedeemer.s.sol:DeployRedeemer \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast
