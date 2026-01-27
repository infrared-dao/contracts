#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

export TOKEN_ADDRESS="0xa1B644AEC990Ad6023811cED36E6A2d6D128C7C9"
export OWNER_ADDRESS="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
export MERKLE_ROOT="0x09d2f7effdcd1bc117d057f796c9597acff45a41532034706708d7563e41b602"
export TOTAL_ALLOCATION=39015244069344710774117962
export CLAIM_WINDOW_DAYS=26
export AUTO_FUND="false"

# Run the deployment script
FOUNDRY_PROFILE=production forge script script/deploy/DeployMerkleDistributor.s.sol:DeployMerkleDistributor \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast
