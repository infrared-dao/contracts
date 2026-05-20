set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

WEIGHT=200000  # 20% (denominator is 1e6)

# forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
#     --sig "updateIRBribeSplit(bool,address,address,uint256)" "false" $SAFE $INFRARED $WEIGHT  \
#     --fork-url $RPC_URL \
#     -vvvv

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "updateIRBribeSplit(bool,address,address,uint256)" "true" $SAFE $INFRARED $WEIGHT  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
