#!/usr/bin/env bash
source .env

# bepolia
RPC_URL="https://bepolia.rpc.berachain.com"
WITHDRAWOR=0x901528D1c588662FF75b19Ade33618115131dA84
IBERA=0x7292B549F9F59fC22bABCD7b6706e7D6889C2624
DEPOSITOR=0x51761dC3fFB5B54186a70ef1d55c44153671D1FF

# mainnet
# RPC_URL="https://rpc.berachain.com"
# IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"

# common
AMOUNT=4500123663637000000000
PROOFS_PATH="/tests/data/proof5.json"

forge script script/keeper/InfraredBERAKeeper.s.sol:InfraredBERAKeeper \
    --sig "executeWithdrawProofs(address,uint256,string)" $WITHDRAWOR $AMOUNT $PROOFS_PATH \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast -vvvv