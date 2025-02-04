#!/usr/bin/env bash
source ./keeper_common.sh

PUBKEYS=(
    "0xad8af2d381461965e08126e48bc95646c2ca74867255381397dc70e711bab07015551a8904c167459f5e6da4db436300"
)
AMOUNTS=(
    "1000000000000000000"
)

forge script $SCRIPT \
    --sig "queueBoosts(bytes[],uint128[],address)" "${PUBKEYS[@]}" "${AMOUNTS[@]}" $SAFE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast