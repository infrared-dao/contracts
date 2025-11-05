set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
BRIBE_COLLECTOR_PROXY="0x609dF5AbC810aB14968B3f71ec7b3Cec4E892377"
BRIBE_COLLECTOR_V1_3_IMPLEMENTATION="0xEa4941c7f4D2926b6A72faB48f7E48aeD96C509E"

RPC_URL="https://bepolia.rpc.berachain.com"

forge script script/upgrades/bribe-collector/v1.3/UpgradeBribeCollectorV1_3Testnet.s.sol:UpgradeBribeCollectorV1_3Testnet \
    --sig "run(address,address)" $BRIBE_COLLECTOR_PROXY $BRIBE_COLLECTOR_V1_3_IMPLEMENTATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast  -vvvv

