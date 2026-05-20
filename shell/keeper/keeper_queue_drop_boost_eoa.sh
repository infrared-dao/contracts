#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredKeeperScriptEOA.s.sol:InfraredKeeperScriptEOA"

PUBKEYS=(
    "0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f"
)

AMOUNTS=(
    178865699943341153058816
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"
IFS=, AMOUNTS_STR="${AMOUNTS[*]}"

forge script $SCRIPT \
    --sig "queueDropBoosts(bytes[],uint128[])" "[$PUBKEYS_STR]" "[$AMOUNTS_STR]" \
    --rpc-url $RPC_URL \
    --keystore $KEYSTORE --password $PASSWORD \
    --broadcast -vvvv --sender 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7