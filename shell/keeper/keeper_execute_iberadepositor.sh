#!/usr/bin/env bash
source ./shell/keeper/keeper_common.sh

IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"

# stakelabs
# PUBKEY="0x84d0f5ed328e029f104f7a3bb5778d188b2197415119b95a9719be47fd0e16e3fbda08dbf5bdfde0a7dab95db1807e47"
# PUBKEY="0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f"
# rockaway
PUBKEY="0x8ccaba10bddc33a4f8d2acdd78593879a84c7466f641f1d9b4238b20ee2d0706894b3e55b0744098c50b9b4821da3207"
# luga
# PUBKEY="0x928d6f66bfd9cb1ef18da6843ad9db6c1b6ec7e3093705c95224e8f20232f243e7a627d09144360d4c1775d8fafdb0e7"
# pier 2
# PUBKEY="0x875aaf00241b14ccd86176e4baed170df6735529afd0f38f01ecfe881cbb613058922a0372814b967e3ae9e880d88658"
# AMOUNT=10000000000000000000000

AMOUNT=3973009694796430000000000

forge script $SCRIPT \
    --sig "depositValidator(bytes,uint256,address)" $PUBKEY $AMOUNT $SAFE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv