#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredKeeperScriptEOA.s.sol:InfraredKeeperScriptEOA"

PUBKEYS=(
    "0x84acfd38a13af12add8d82e1ef0842c4dfc1e4175fae5b8ab73770f9050cbf673cafdbf6d8ab679fe9ea13208f50b485"
)

AMOUNTS=(
    5224895212967412105216
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"
IFS=, AMOUNTS_STR="${AMOUNTS[*]}"

forge script $SCRIPT \
    --sig "cancelBoosts(bytes[],uint128[])" "[$PUBKEYS_STR]" "[$AMOUNTS_STR]" \
    --rpc-url $RPC_URL \
    --keystore $KEYSTORE --password $PASSWORD \
    --broadcast -vvvv --sender 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7