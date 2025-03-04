#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

VAULT="0x5614314Eef828c747602a629B1d974a3f28fF6E2"
ASSET="0x38fdD999Fe8783037dB1bBFE465759e312f2d809"

forge script $SCRIPT \
    --sig "harvestOldVault(address,address,address)" $SAFE $VAULT $ASSET \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast