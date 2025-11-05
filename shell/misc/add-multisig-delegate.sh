set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
ADMIN_ADDRESS="0x1eCF087ea1194AB182A53De849d61deB917D733F"
DELEGATE_ADDRESS="0x54a4c29196aAD6FA77F9b4e35288E5234ac4F31a"
SAFE_TX_SERVICE="https://transaction.bp.w3us.site/"

# RPC_URL="https://rpc.berachain.com"
RPC_URL="https://rpc.berachain.com"


forge script script/misc/AddSafeDelegate.s.sol:AddSafeDelegate \
    --sig "run(address,address,address,string)" $SAFE $DELEGATE_ADDRESS $ADMIN_ADDRESS "$SAFE_TX_SERVICE" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
