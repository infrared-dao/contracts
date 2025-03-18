set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
SIG="0x832212414fcd12ee62b017b21b28220377da901516019838a8fe01d2e4852199ced7aaa69353cadb7877f83ab82ef4b307c0c61e67d6cfb686169551320570493301069669396ebd113c4ecd268e1c1ae2354be5f733d9aadab4d41e8925f72e"
PUBKEY="0xaddc88b5a74211b80ed2b8c5169b85380b7428a8b0a3381a4470d52203eb230f136b423370308783082866f716b06651"


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setDepositSignature(address,address,bytes,bytes)" $SAFE $IBERA $PUBKEY $SIG \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
