set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
BRIBE_COLLECTOR_PROXY="0x609dF5AbC810aB14968B3f71ec7b3Cec4E892377"
BRIBE_COLLECTOR_V1_2_IMPLEMENTATION="0x05C7f5e53617Dc8197092D3628ee1d25322c051E"

RPC_URL="https://bepolia.rpc.berachain.com"

forge script script/upgrades/bribe-collector/v1.2/UpgradeBribeCollectorTestnet.s.sol:UpgradeBribeCollectorTestnet \
    --sig "run(address,address)" $BRIBE_COLLECTOR_PROXY $BRIBE_COLLECTOR_V1_2_IMPLEMENTATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast  -vvvv
