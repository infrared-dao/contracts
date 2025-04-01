set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"
HONEY="0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce"

WEIGHT=100000  # 10% (denominator is 1e6)

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "updateInfraredBERABribesWeight(address,address,uint256)" $SAFE $INFRARED $WEIGHT  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv