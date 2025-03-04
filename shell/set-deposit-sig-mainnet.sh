set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
SIG="0xa58cf9d41726f3f7cdf47003b427072daa6228045efffb568b0bea6c168f1c91e3cdc332733779a78e1da5631cab1a7708289dd0089527d20b1f5dc639321fb2f325296a4537a09bf2b0e4b60013ca775450927a1a4b742bca2b97f78ece1b2e"
PUBKEY="0x875aaf00241b14ccd86176e4baed170df6735529afd0f38f01ecfe881cbb613058922a0372814b967e3ae9e880d88658"


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setDepositSignature(address,address,bytes,bytes)" $SAFE $IBERA $PUBKEY $SIG \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
