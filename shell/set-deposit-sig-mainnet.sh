set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="http://35.203.86.197:8545/"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
SIG="<Deposit sig for 10k bera>"
PUBKEY="<pubkey>"


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setDepositSignature(address,address,bytes,bytes)" $SAFE $IBERA $PUBKEY $SIG \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast 
