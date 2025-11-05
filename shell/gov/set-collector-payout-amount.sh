set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
COLLECTOR="0x8d44170e120B80a7E898bFba8cb26B01ad21298C"

PAYOUT_AMOUNT=3000000000000000000000

# function setPayoutAmount(address safe, address collector, uint256 _newPayoutAmount)

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setPayoutAmount(address,address,uint256)" $SAFE $COLLECTOR $PAYOUT_AMOUNT  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv