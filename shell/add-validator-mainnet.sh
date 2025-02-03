set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="http://35.203.86.197:8545/"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
ADDR="<Operator reward address>"
PUBKEY="<pubkey>"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "addValidators(address,address,bytes)" $SAFE $INFRARED $ADDR $PUBKEY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast 
