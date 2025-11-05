#!/bin/bash
set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
RPC_URL="https://rpc.berachain.com"
VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan'

# Run the deployment script
FOUNDRY_PROFILE=production forge script script/deploy/InfraredBERARateProviderDeployer.s.sol:InfraredBERARateProviderDeployer \
    --sig "run(address)" $IBERA \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --verifier-url $VERIFYER_URL \
    --etherscan-api-key "verifyContract" \
    --broadcast
