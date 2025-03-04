set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
BRIBE_COLLECTOR_PROXY="0x8d44170e120B80a7E898bFba8cb26B01ad21298C"
BRIBE_COLLECTOR_V1_2_IMPLEMENTATION=""

RPC_URL="https://rpc.berachain.com"

forge script script/UpgradeBribeCollector.s.sol:UpgradeBribeCollector \
    --sig "run(address,address,address)" $SAFE $BRIBE_COLLECTOR_PROXY $BRIBE_COLLECTOR_V1_2_IMPLEMENTATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
