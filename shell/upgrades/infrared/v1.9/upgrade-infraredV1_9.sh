set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
KEEPER=0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7
IBGT=0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
WBERA=0x6969696969696969696969696969696969696969
RECEIVOR=0xf6a4A6aCECd5311327AE3866624486b6179fEF97
BRIBE_COLLECTOR=0x8d44170e120B80a7E898bFba8cb26B01ad21298C

RPC_URL="https://rpc.berachain.com"

forge clean

FOUNDRY_PROFILE=production forge build --sizes

# deploy wibgt and batch claimor
# FOUNDRY_PROFILE=production forge script script/UpgradeInfraredV1_9.s.sol:UpgradeInfraredV1_9 \
#     --sig "deployWibgt(address)" $IBGT \
#     --fork-url $RPC_URL -vvvv \
#     --private-key $PRIVATE_KEY --verify \
#     --broadcast

WIBGT=0x4f3C10D2bC480638048Fa67a7D00237a33670C1B

# function upgradeInfrared(bool _send, address _infraredProxy, address _wibgt)

# # dry run
FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.9/UpgradeInfraredV1_9.s.sol:UpgradeInfraredV1_9 \
    --sig "upgradeInfrared(bool,address,address,address,address)" "false" $INFRARED $WIBGT $IBGT $BRIBE_COLLECTOR \
    --fork-url $RPC_URL -vvvv

# # live
# FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.9/UpgradeInfraredV1_9.s.sol:UpgradeInfraredV1_9 \
#     --sig "upgradeInfrared(bool,address,address,address,address)" "true" $INFRARED $WIBGT $IBGT $BRIBE_COLLECTOR \
#     --rpc-url $RPC_URL -vvvv \
#     --private-key $PRIVATE_KEY --verify \
#     --broadcast
