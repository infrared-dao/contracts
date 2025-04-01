set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

PUBKEYS=(
    "0x86888df491e8ccdc5bb940b9dda51fa7449518593820c9e4e9033a7b87f5e9f8debbba6a4f68218711896906ad40ce71"
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "queueValCommissions(address,address,bytes[])" $SAFE $INFRARED "[$PUBKEYS_STR]"  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv