#!/bin/bash

set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SENDER="0x1eCF087ea1194AB182A53De849d61deB917D733F"
AMOUNT_IBERA=7027300000000
AMOUNT_BERA=7027300000000
POOL_ID="0x1207c619086a52edef4a4b7af881b5ddd367a919000200000000000000000006" # iBGT pool id
AMOUNTS_IN="[$AMOUNT_BERA,$AMOUNT_IBERA]"

VAULT_ADDRESS="0x4Be03f781C497A489E3cB0287833452cA9B9E80B"
POOL_FACTORY="0xa966fA8F2d5B087FFFA499C0C1240589371Af409"
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
WBERA="0x6969696969696969696969696969696969696969"

RPC_URL="http://35.203.86.197:8545/"

VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan'

USER_DATA=$(cast abi-encode "func(uint256,uint256[])" 0 "$AMOUNTS_IN")


# cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $WBERA "deposit()" --value $AMOUNT_BERA

cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $IBGT "approve(address,uint256)" $VAULT_ADDRESS $AMOUNT_IBERA

# cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $WBERA "approve(address,uint256)" $VAULT_ADDRESS $AMOUNT_BERA

cast send $VAULT_ADDRESS "joinPool(bytes32,address,address,(address[],uint256[],bytes,bool))" \
    $POOL_ID \
    $SENDER \
    $SENDER \
    "([$WBERA, $IBGT], $AMOUNTS_IN, $USER_DATA, "false")" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

    