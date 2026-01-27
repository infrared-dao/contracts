#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

GOV="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

# Run the deployment script
FOUNDRY_PROFILE=production forge script script/deploy/InfraredGovernanceTokenDeployer.s.sol:InfraredGovernanceTokenDeployer \
    --sig "run(address)" $GOV \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify -vvvv \
    --broadcast
