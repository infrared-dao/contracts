set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
BASE_COLLECTOR="0x7332051C4EeD9CD40B28BA0a1c5d042666897dA8"
KEEPER="0x3339dD891329987d0E667209280D14849B75bD62"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "grantKeeperRoleBaseCollector(address,address,address)" $SAFE $BASE_COLLECTOR $KEEPER \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv