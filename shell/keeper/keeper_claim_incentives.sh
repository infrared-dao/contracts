#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

# send to multisig
RECIPIENT="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"

INCENTIVE_TOKENS=(
    "0x18878Df23e2a36f81e820e4b47b4A40576D3159C"  # OHM
    "0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce"  # HONEY
    "0xb749584F9fC418Cf905d54f462fdbFdC7462011b"  # bm
)

IFS=, INCENTIVE_TOKENS_STR="${INCENTIVE_TOKENS[*]}"

# numbers are approximated
INCENTIVE_TOKEN_AMOUNTS=(
    "2039269773692"
    "437194536750353999"
    "735684835522545540245000"
)

IFS=, INCENTIVE_TOKEN_AMOUNTS_STR="${INCENTIVE_TOKEN_AMOUNTS[*]}"

forge script $SCRIPT \
    --sig "claimIncentives(address,address[],uint256[])" $RECIPIENT "[$INCENTIVE_TOKENS_STR]" "[$INCENTIVE_TOKEN_AMOUNTS_STR]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast