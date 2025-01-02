set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Cartio RPC URL
RPC_URL="https://amberdew-eth-cartio.berachain.com"

forge script -vvvv script/InfraredKeeperScript.s.sol:InfraredKeeperScript \
    --sig "harvest()" \
    --fork-url $RPC_URL \
    --private-key $PRIVATE_KEY 
    # --broadcast 
