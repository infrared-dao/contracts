set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

STAKING_TOKEN=0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8
REWARD_TOKEN=0x688e72142674041f8f6Af4c808a4045cA1D6aC82
REWARD_DURATION=86400

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "addReward(address,address,address,address,uint256)" $SAFE $INFRARED $STAKING_TOKEN $REWARD_TOKEN $REWARD_DURATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
