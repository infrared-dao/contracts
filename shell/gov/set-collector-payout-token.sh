set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
COLLECTOR="0x8d44170e120B80a7E898bFba8cb26B01ad21298C"
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"
WBERA="0x6969696969696969696969696969696969696969"

PAYOUT_TOKEN=$WBERA

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setPayoutToken(address,address,address)" $SAFE $COLLECTOR $PAYOUT_TOKEN  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv