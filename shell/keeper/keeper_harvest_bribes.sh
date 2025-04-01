#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

INCENTIVE_TOKENS=(
    "0x18878Df23e2a36f81e820e4b47b4A40576D3159C"  # OHM
    "0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce"  # HONEY
    "0xb749584F9fC418Cf905d54f462fdbFdC7462011b"  # bm
    "0x6969696969696969696969696969696969696969" # WBERA
)

IFS=, INCENTIVE_TOKENS_STR="${INCENTIVE_TOKENS[*]}"

forge script $SCRIPT \
    --sig "harvestBribes(address[])" "[$INCENTIVE_TOKENS_STR]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast -vvvv