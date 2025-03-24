set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"
ASSETS=(
    "0x97431F104be73FC0e6fc731cE84486DA05C48871" # Stone-WETH
    "0x57161d6272F47cd48BA165646c802f001040C2E0" # BeraETH-Stone
    "0x03bCcF796cDef61064c4a2EffdD21f1AC8C29E92" # BeraETH-WETH
)

IFS=, ASSETS_STR="${ASSETS[*]}"

# migrateMultipleVaults(address safe, address infrared, address[] _assets, uint8 versionToUpgradeTo)

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "migrateMultipleVaults(address,address,address[],uint8)" $SAFE $INFRARED "[$ASSETS_STR]" 1  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv