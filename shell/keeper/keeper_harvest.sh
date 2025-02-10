#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

# List of staking tokens that have a corresponding InfraredVault to harvest
STAKING_TOKENS=(
    "0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4"  # (50WETH-50WBERA-WEIGHTED)
    "0xF961a8f6d8c69E7321e78d254ecAfBcc3A637621"  # (USDC.e-HONEY-STABLE)
    "0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8"  # (BYUSD-HONEY-STABLE)
    "0x2c4a603A2aA5596287A06886862dc29d56DbC354"  # (50WBERA-50HONEY-WEIGHTED)
    "0x38fdD999Fe8783037dB1bBFE465759e312f2d809"  # (50WBTC-50WBERA-WEIGHTED)
)

IFS=, STAKING_TOKENS_STR="${STAKING_TOKENS[*]}"

forge script $SCRIPT \
    --sig "harvest(address[])" "[$STAKING_TOKENS_STR]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast