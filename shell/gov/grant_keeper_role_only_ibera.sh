set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
KEEPER="0x0C224f0F468675aD6299f7A93D23a829964a2369"

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "grantKeeperRoleOnlyIbera(address,address,address)" $SAFE $IBERA $KEEPER \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 