#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://bepolia.rpc.berachain.com"

GOV="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
INFRARED="0xb4fe1c9a7068586f377eCaD40632347be2372E6C"

# Run the deployment script
forge script script/deploy/InfraredGovernanceTokenDeployer.s.sol:InfraredGovernanceTokenDeployer \
    --sig "run(address)" $GOV \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast
    