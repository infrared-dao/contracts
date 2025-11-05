set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
BRIBE_COLLECTOR_PROXY="0x8d44170e120B80a7E898bFba8cb26B01ad21298C"
BRIBE_COLLECTOR_V1_3_IMPLEMENTATION="0xB3Cec5aC14897ebc145DA41c46e97A37Cd803b3F"

KEEPERS=(
    "0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7"  # EOA keeper
    "0x3339dD891329987d0E667209280D14849B75bD62"  # Latest auction bot contract
    "0x1d4F3c70cbD3aa0c5231B496A2AD48128121C1b0"  # Legacy auction bot contract
)

IFS=, KEEPERS_STR="${KEEPERS[*]}"

RPC_URL="https://rpc.berachain.com"

forge script script/upgrades/bribe-collector/v1.3/UpgradeBribeCollectorV1_3.s.sol:UpgradeBribeCollectorV1_3 \
    --sig "run(address,address,address,address[])" $SAFE $BRIBE_COLLECTOR_PROXY $BRIBE_COLLECTOR_V1_3_IMPLEMENTATION "[$KEEPERS_STR]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
