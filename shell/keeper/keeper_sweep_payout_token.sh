#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh


forge script $SCRIPT \
    --sig "sweepPayoutToken()" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast -vvvv