#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/InfraredKeeperScriptEOA.s.sol:InfraredKeeperScriptEOA"

PUBKEYS=(
    "0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f"
)

forge script $SCRIPT \
    --sig "activateAndMaxBoost(bytes[])" "[${PUBKEYS[@]}]" \
    --rpc-url $RPC_URL \
    --keystore $KEYSTORE --password $PASSWORD \
    --broadcast