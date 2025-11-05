set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
SIG="0xb8cc3eb141c2620bee8d7a0989d17209ff0320ed0e42f147981458dacb665be411de98fabde12acd5de732dde4409acb0045b7bf796f15534c2d6e870c263aab4efc8cfeb5c09fb755b38e3657d8e3bb53f5e35fcfe5a133981eddcb4595181a"
PUBKEY="0x86888df491e8ccdc5bb940b9dda51fa7449518593820c9e4e9033a7b87f5e9f8debbba6a4f68218711896906ad40ce71"


forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setDepositSignature(address,address,bytes,bytes)" $SAFE $IBERA $PUBKEY $SIG \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
