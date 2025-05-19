#!/bin/bash

set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
OWNER="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"

VAULT_ADDRESS="0x4Be03f781C497A489E3cB0287833452cA9B9E80B"
POOL_FACTORY="0xDfA30BDa0375d4763711AB0CC8D91B20bfCC87E1"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
WBERA="0x6969696969696969696969696969696969696969"
POOL_NAME="WBERA | iBERA"
POOL_SYMBOL="WBERA-iBERA-STABLE"
AMP=50
SWAP_FEE="3000000000000000" # 0.3% fee
SALT=$(cast keccak "iBERA-WBERA-v2")

IBERA_RATE_PROVIDER="0x776fD57Bbeb752BDeEB200310faFAe9A155C50a0"

RPC_URL="https://rpc.berachain.com"

VERIFYER_URL='https://api.routescan.io/v2/network/mainnet/evm/80094/etherscan'

echo "Deploying Weighted Pool via Factory..."

cast send $POOL_FACTORY "create(string,string,address[],uint256,address[],uint256[],bool,uint256,address,bytes32)" \
    "$POOL_NAME" \
    "$POOL_SYMBOL" \
    "[$WBERA, $IBERA]" \
    "$AMP" \
    "[0x0000000000000000000000000000000000000000, $IBERA_RATE_PROVIDER]" \
    "[100, 100]" \
    "true" \
    "$SWAP_FEE" \
    "$OWNER" \
    "$SALT" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY

    