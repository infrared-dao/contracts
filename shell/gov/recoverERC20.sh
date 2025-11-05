set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

TO=$SAFE
TOKEN="0x0000382FbB422B4f593931FC6f2d25CC16600000"
AMOUNT=809403213445001301746586

# recoverERC20(
#         address safe,
#         address payable infrared,
#         address _to,
#         address _token,
#         uint256 _amount

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "recoverERC20(address,address,address,address,uint256)" $SAFE $INFRARED $TO $TOKEN $AMOUNT  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv