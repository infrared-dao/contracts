set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

forge clean

FOUNDRY_PROFILE=production forge script script/upgrades/staking/UpgradeInfraredBERA.s.sol:UpgradeInfraredBERA \
    --sig "deploy()" \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY --verify -vvvv
