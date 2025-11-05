set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"

STAKING_TOKEN=$IBGT
REWARD_TOKEN=$IBGT


forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "removeReward(address,address,address,address)" $SAFE $INFRARED $STAKING_TOKEN $REWARD_TOKEN \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
