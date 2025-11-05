set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
INFRARED_V3_IMPLEMENTATION="0x67B4e6721AD3a99B7fF3679caee971b07fd85cD1"

RPC_URL="https://rpc.berachain.com"

PUBKEYS=(
    "0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f"
    "0x928d6f66bfd9cb1ef18da6843ad9db6c1b6ec7e3093705c95224e8f20232f243e7a627d09144360d4c1775d8fafdb0e7"
    "0x875aaf00241b14ccd86176e4baed170df6735529afd0f38f01ecfe881cbb613058922a0372814b967e3ae9e880d88658"
    "0x8ccaba10bddc33a4f8d2acdd78593879a84c7466f641f1d9b4238b20ee2d0706894b3e55b0744098c50b9b4821da3207"
    "0x90d64ab2a8ab9b5faace9225d205d47dc0b8155592b354b860134928f7f39f15f54d909dad7897868aba6dc7e7eef6c8"
    "0x998adf736d60eecdfd3ab5136a779aa23235c44bb6de08def2069f73e946de963b35a68d5a66d611d3a7cd45035dca8f"
    "0xaddc88b5a74211b80ed2b8c5169b85380b7428a8b0a3381a4470d52203eb230f136b423370308783082866f716b06651"
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"

forge script script/upgrades/infrared/v1.3/UpgradeInfraredV1_3.s.sol:UpgradeInfraredV1_3 \
    --sig "run(address,address,address,bytes[])" $SAFE $INFRARED $INFRARED_V3_IMPLEMENTATION "[$PUBKEYS_STR]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast  -vvvv
