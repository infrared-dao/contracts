set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
COLLECTOR="0x7332051C4EeD9CD40B28BA0a1c5d042666897dA8"

PAYOUT_AMOUNT=100000000000000000000

# function setBaseCollectorPayoutAmount(address safe, address collector, uint256 _newPayoutAmount)

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setBaseCollectorPayoutAmount(address,address,uint256)" $SAFE $COLLECTOR $PAYOUT_AMOUNT  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv