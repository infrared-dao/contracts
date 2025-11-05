set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
INFRARED_V5_IMPLEMENTATION="0xB0713baFa14f1a36ABfCe7800A0e8d2c539a02Dd"

RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.5/UpgradeInfraredV1_5.s.sol:UpgradeInfraredV1_5 \
    --sig "run(address,address,address)" $SAFE $INFRARED $INFRARED_V5_IMPLEMENTATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
