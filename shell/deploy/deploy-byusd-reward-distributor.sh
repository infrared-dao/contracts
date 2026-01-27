#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
RPC_URL="https://rpc.berachain.com"

# function run(
#     address infraredGovernance,
#     address infrared,
#     address stakingAsset,
#     address rewardsToken,
#     address underlyingToken,
#     address wrapper,
#     address keeper
# )

SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

STAKING_TOKEN=0x939F1B6f513C3d62EB25C7E057Ed8bb24021A000
REWARD_TOKEN=0x334404782aB67b4F6B2A619873E579E971f9AAB7
UNDERLYING=0x688e72142674041f8f6Af4c808a4045cA1D6aC82
KEEPER=0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7

# Run the deployment script
FOUNDRY_PROFILE=production forge script script/deploy/DeployBYUSDRewardDistributor.s.sol:DeployBYUSDRewardDistributor \
    --sig "run(address,address,address,address,address,address)" $SAFE $INFRARED $STAKING_TOKEN $REWARD_TOKEN $UNDERLYING $KEEPER \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verify \
    --broadcast -vvvv
