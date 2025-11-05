#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredKeeperScriptEOA.s.sol:InfraredKeeperScriptEOA"

PUBKEYS=(
    # "0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f"
    # "0x928d6f66bfd9cb1ef18da6843ad9db6c1b6ec7e3093705c95224e8f20232f243e7a627d09144360d4c1775d8fafdb0e7"
    "0x90d64ab2a8ab9b5faace9225d205d47dc0b8155592b354b860134928f7f39f15f54d909dad7897868aba6dc7e7eef6c8"
)

forge script $SCRIPT \
    --sig "activateBoost(bytes[])" "[${PUBKEYS[@]}]" \
    --rpc-url $RPC_URL \
    --keystore $KEYSTORE --password $PASSWORD \
    --broadcast -vvvv