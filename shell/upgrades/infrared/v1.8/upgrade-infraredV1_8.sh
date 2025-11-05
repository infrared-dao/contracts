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

# PAYOUT_AMOUNT=1000000000000000000000
# PAYOUT_TOKEN=$IBGT

RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production

forge clean

forge build --sizes

# step 1: deploy new collector imp
forge script script/upgrades/infrared/v1.8/UpgradeInfraredV1_8.s.sol:UpgradeInfraredV1_8 \
    --sig "deployBribeCollectorImp()" \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY --verify \
    --broadcast


BRIBE_COLLECTOR_IMP=

# step 2: deploy new Infrared imp (note, upgrade and initialize are protected by onlyGov)
forge script script/upgrades/infrared/v1.8/UpgradeInfraredV1_8.s.sol:UpgradeInfraredV1_8 \
    --sig "deployInfraredImp()" \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY --verify \
    --broadcast
# todo: capture returned imp address
INFRAREDV1_8_IMP=

# step 3: upgrade bribe collector and infrared
# function upgradeInfrared(
#     bool _send,
#     address _bribeCollectorProxy,
#     address _infraredProxy,
#     address newInfraredImp,
#     address newBribeCollectorImp
# )

# # first pass simulate
forge script script/upgrades/infrared/v1.8/UpgradeInfraredV1_8.s.sol:UpgradeInfraredV1_8 \
    --sig "upgradeInfrared(bool,address,address,address,address)" false $BRIBE_COLLECTOR $INFRARED $INFRAREDV1_8_IMP $BRIBE_COLLECTOR_IMP \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY 

# second pass execute
forge script script/upgrades/infrared/v1.8/UpgradeInfraredV1_8.s.sol:UpgradeInfraredV1_8 \
    --sig "upgradeInfrared(bool,address,address,address,address)" true $BRIBE_COLLECTOR $INFRARED $INFRAREDV1_8_IMP $BRIBE_COLLECTOR_IMP \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY 
