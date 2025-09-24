set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
REDEEEMER_CONTRACT="0x5a2DA5e3CffA06f625eF4f2142675950C03370cc"
REDEEMER_EOA="0xeA23325Ff22F17A8a8F78A464dE74E685d6c0307"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "grantRedeemerRole(address,address,address)" $SAFE $REDEEEMER_CONTRACT $REDEEMER_EOA \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
