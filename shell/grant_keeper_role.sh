set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="http://35.203.86.197:8545/"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
KEEPER="0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "grantKeeperRole(address,address,address,address)" $SAFE $INFRARED $IBERA $KEEPER \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 