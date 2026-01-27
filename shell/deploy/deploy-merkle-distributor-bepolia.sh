#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://bepolia.rpc.berachain.com"

export TOKEN_ADDRESS=0xaA4B088BaC22048fF698B166276FAE67302f8FD9
export OWNER_ADDRESS="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
export MERKLE_ROOT="0x721f9bf0d321fead05079ea26349712d4a036bcb89abdb2c0e815787e23406b4"
export TOTAL_ALLOCATION="36003964120101521146973891"
export CLAIM_WINDOW_DAYS=90
export AUTO_FUND="true"

# mint IR airdrop amount to deployer
cast send $TOKEN_ADDRESS \
    "mint(address,uint256)" $OWNER_ADDRESS $TOTAL_ALLOCATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

# Run the deployment script
forge script script/deploy/DeployMerkleDistributor.s.sol:DeployMerkleDistributor \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast
