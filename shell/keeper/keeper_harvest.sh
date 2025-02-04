#!/usr/bin/env bash
source ./keeper_common.sh

# List of staking tokens that have a corresponding InfraredVault to harvest
STAKING_TOKENS=(
    "0x"  # KODI-WETH-HONEY
)

forge script $SCRIPT \
    --sig "harvest(address[])" "${STAKING_TOKENS[@]}" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast