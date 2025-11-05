set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://bepolia.rpc.berachain.com"

VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80069/etherscan'

FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.5/DeployInfraredV1_5.s.sol:DeployInfraredV1_5 \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $VERIFYER_URL \
    --etherscan-api-key "verifyContract" -vvvv
    