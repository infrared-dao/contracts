set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
KEEPER="0x78B5ebb84Db848c55e553fe1928474F926d59D84"

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "grantKeeperRoleOnlyInfrared(address,address,address)" $SAFE $INFRARED $KEEPER \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 