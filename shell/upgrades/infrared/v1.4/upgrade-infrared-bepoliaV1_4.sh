set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
INFRARED="0xb4fe1c9a7068586f377eCaD40632347be2372E6C"
INFRARED_V4_IMPLEMENTATION=""

RPC_URL="https://bepolia.rpc.berachain.com"

forge script script/upgrades/infrared/v1.4/UpgradeInfraredTestnetV1_4.s.sol:UpgradeInfraredTestnetV1_4 \
    --sig "run(address,address)" $INFRARED $INFRARED_V4_IMPLEMENTATION\
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
