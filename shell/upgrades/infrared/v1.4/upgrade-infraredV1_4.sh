set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
INFRARED_V4_IMPLEMENTATION=""

RPC_URL="https://rpc.berachain.com"

forge script script/upgrades/infrared/v1.4/UpgradeInfraredV1_4.s.sol:UpgradeInfraredV1_4 \
    --sig "run(address,address,address)" $SAFE $INFRARED $INFRARED_V4_IMPLEMENTATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
