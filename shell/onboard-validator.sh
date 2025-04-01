set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"

# king
# PUBKEY="0x967fb9134794ac697aadf15782b6f03da5494a094eb588045ac209bc80315d3c33b4cbf78db90400428c92011d6fde58"
# kudasai
PUBKEY="0x8e98ca2aaa76909360e4b1cf2e87ed2839222ab37495b067b3257cef256dbeabeca55ec72465d0fb2321a9b73f495e0f"
ADDR="0xD7C33b3A09Bf64B90dAbEe030607B735deE2831A"
SIG="0xb36118631c46ddd1aa86d07b3c304cf2b11507e054a7301b486979454dd8a541148ac84873fa38a1eadaf8ae1daf0f0c12c99a8fa427a5e3b5fac0ded1304806987972690bac1e43b1eb061f80979023ee43c9b42948b3df13e04cfb8efc2547"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "onboardValidator(address,address,address,address,bytes,bytes)" $SAFE $INFRARED $IBERA $ADDR $PUBKEY $SIG \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
