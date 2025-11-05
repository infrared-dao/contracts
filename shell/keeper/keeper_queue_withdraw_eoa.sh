#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredBERAKeeper.s.sol:InfraredBERAKeeper"

PUBKEY=0x84d0f5ed328e029f104f7a3bb5778d188b2197415119b95a9719be47fd0e16e3fbda08dbf5bdfde0a7dab95db1807e47
WITHDRAWOR=0x8c0E122960dc2E97dc0059c07d6901Dce72818E1
IBERA=0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5

forge script $SCRIPT \
    --sig "queueExitRebalance(address,address,bytes)" $WITHDRAWOR $IBERA $PUBKEY \
    --rpc-url $RPC_URL \
    --keystore $KEYSTORE --password $PASSWORD \
    --broadcast -vvvv \
    --sender 0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7