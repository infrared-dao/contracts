set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

PUBKEYS=(
    "0x8e98ca2aaa76909360e4b1cf2e87ed2839222ab37495b067b3257cef256dbeabeca55ec72465d0fb2321a9b73f495e0f"
    "0x90e5fba025da21dbe20e4b791792d821cf6e6cde7ea94814dba26d790152e5baa07b053bfc2b32332ca38fef51d9b76a"
    "0x95d787a0b2a6606aa0e711ba429b8fc598615589e9ea1a182fece3df33c0db8e8be642294fe943284d5ff58a778cf247"
)

IFS=, PUBKEYS_STR="${PUBKEYS[*]}"


forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "queueValCommissions(address,address,bytes[])" $SAFE $INFRARED "[$PUBKEYS_STR]"  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv