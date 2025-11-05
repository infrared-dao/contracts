set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED="0xb4fe1c9a7068586f377eCaD40632347be2372E6C"
INFRARED_V5_IMPLEMENTATION="0x934448A1De1031244C16d95fB017177d6b6cdfE7"

RPC_URL="https://bepolia.rpc.berachain.com"

forge script script/upgrades/infrared/v1.5/UpgradeInfraredTestnetV1_5.s.sol:UpgradeInfraredTestnetV1_5 \
    --sig "run(address,address)" $INFRARED $INFRARED_V5_IMPLEMENTATION\
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
