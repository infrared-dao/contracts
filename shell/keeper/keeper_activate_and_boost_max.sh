#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

PUBKEYS=(
    "0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f"
)

forge script $SCRIPT \
    --sig "activateAndMaxBoost(bytes[],address)" "[${PUBKEYS[@]}]" $SAFE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast