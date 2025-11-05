#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredKeeperScriptEOA.s.sol:InfraredKeeperScriptEOA"

PUBKEYS=(
    "0x84d0f5ed328e029f104f7a3bb5778d188b2197415119b95a9719be47fd0e16e3fbda08dbf5bdfde0a7dab95db1807e47"
)

AMOUNTS=(
    4163121358860021446864
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"
IFS=, AMOUNTS_STR="${AMOUNTS[*]}"

forge script $SCRIPT \
    --sig "queueDropBoosts(bytes[],uint128[])" "[$PUBKEYS_STR]" "[$AMOUNTS_STR]" \
    --rpc-url $RPC_URL \
    --keystore $KEYSTORE --password $PASSWORD \
    --broadcast -vvvv --sender 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7