set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
INFRARED="0xb4fe1c9a7068586f377eCaD40632347be2372E6C"
INFRARED_V2_IMPLEMENTATION="0xa233c39402D7d7685941a09e125F79237D924322"

RPC_URL="https://bepolia.rpc.berachain.com"

STAKING_TOKENS=()

IFS=, STAKING_TOKENS_STR="${STAKING_TOKENS[*]}"

forge script script/UpgradeInfraredTestnet.s.sol:UpgradeInfraredTestnet \
    --sig "run(address,address,address[])" $INFRARED $INFRARED_V2_IMPLEMENTATION "[]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
