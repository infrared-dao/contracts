#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

PUBKEYS=(
    "0x84acfd38a13af12add8d82e1ef0842c4dfc1e4175fae5b8ab73770f9050cbf673cafdbf6d8ab679fe9ea13208f50b485"
)
AMOUNTS=(
    "472842893682521669632"
)

forge script $SCRIPT \
    --sig "cancelBoosts(bytes[],uint128[],address)" "[${PUBKEYS[@]}]" "[${AMOUNTS[@]}]" $SAFE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast