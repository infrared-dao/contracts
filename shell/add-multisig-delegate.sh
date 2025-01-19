set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x94092182D03fE8517A0345c455caA8047f9feb5b"
ADMIN_ADDRESS="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
SAFE_TX_SERVICE="https://transaction-bartio.safe.berachain.com/"

# Cartio RPC URL
# RPC_URL="https://amberdew-eth-cartio.berachain.com"
RPC_URL="https://bartio.rpc.berachain.com"


forge script script/AddSafeDelegate.s.sol:AddSafeDelegate \
    --sig "run(address,address,address,string)" $SAFE $ADMIN_ADDRESS $ADMIN_ADDRESS "$SAFE_TX_SERVICE" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
