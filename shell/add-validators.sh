set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Cartio RPC URL
RPC_URL="https://amberdew-eth-cartio.berachain.com"

INFRARED="0xEb68CBA7A04a4967958FadFfB485e89fE8C5f219"
ADDR="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
PUBKEY="0xad8af2d381461965e08126e48bc95646c2ca74867255381397dc70e711bab07015551a8904c167459f5e6da4db436300"

forge script script/InfraredGovernance.s.sol:InfraredGovernance \
    --sig "addValidators(address,address,bytes)" $INFRARED $ADDR $PUBKEY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast 
