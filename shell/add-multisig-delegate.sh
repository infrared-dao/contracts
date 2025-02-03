set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
ADMIN_ADDRESS="<One Safe Owner address>"
DELEGATE_ADDRESS="<delegate account for running scripts to propose txs>"
SAFE_TX_SERVICE="https://transaction.bp.w3us.site/api/v1/safes/"

RPC_URL="http://35.203.86.197:8545/"


forge script script/AddSafeDelegate.s.sol:AddSafeDelegate \
    --sig "run(address,address,address,string)" $SAFE $DELEGATE_ADDRESS $ADMIN_ADDRESS "$SAFE_TX_SERVICE" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
