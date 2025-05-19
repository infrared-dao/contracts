set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

PUBKEYS=(
    "0xab2f79eeae163596276d5a56e52be4796df33377b157531a839a0174a68ca36e245bee122c4b5364176cf25ec2e0e8fc"
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "queueValCommissions(address,address,bytes[])" $SAFE $INFRARED "[$PUBKEYS_STR]"  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv