#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

SAFE=0x182a31A27A0D39d735b31e80534CFE1fCd92c38f
IBERA=0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5

forge clean

FOUNDRY_PROFILE=production forge build

# dry run
FOUNDRY_PROFILE=production forge script script/upgrades/staking/UpgradeInfraredBERAV2_1.s.sol:UpgradeInfraredBERAV2_1 \
    --sig "run(bool,address,address)" "false" $SAFE $IBERA  \
    --fork-url $RPC_URL \
    -vvvv

# live
FOUNDRY_PROFILE=production forge script script/upgrades/staking/UpgradeInfraredBERAV2_1.s.sol:UpgradeInfraredBERAV2_1 \
    --sig "run(bool,address,address)" "true" $SAFE $IBERA \
    --broadcast --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY -vvvv --verify

echo ""
echo "Upgrade complete!"
echo "Transaction has been sent to Safe multisig for approval"
