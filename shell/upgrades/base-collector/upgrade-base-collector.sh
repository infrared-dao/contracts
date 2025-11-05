set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
BASE_COLLECTOR_PROXY="0x7332051C4EeD9CD40B28BA0a1c5d042666897dA8"

RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production forge script script/upgrades/base-collector/UpgradeBaseCollector.s.sol:UpgradeBaseCollector \
    --sig "run(address,address)" $SAFE $BASE_COLLECTOR_PROXY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast --verify -vvvv
