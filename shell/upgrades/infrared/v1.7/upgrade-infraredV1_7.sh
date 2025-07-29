set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
KEEPER=0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7
IBGT=0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
WBERA=0x6969696969696969696969696969696969696969
RECEIVOR=0xf6a4A6aCECd5311327AE3866624486b6179fEF97

PAYOUT_AMOUNT=1000000000000000000000

RPC_URL="https://rpc.berachain.com"

FOUNDRY_PROFILE=production

forge clean

forge build --sizes

# step 1: deploy new collector and proxy
# function deployCollector(
#         address _infraredProxy,
#         address _keeper,
#         address _ibgt,
#         address _wbera,
#         address _receivor,
#         uint256 _payoutAmount
#     ) external returns (address proxyAddr)
forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
    --sig "deployCollector(address,address,address,address,address,uint256)" $INFRARED $KEEPER $IBGT $WBERA $RECEIVOR $PAYOUT_AMOUNT \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY --verfiy \
    --broadcast
# todo: capture returned proxy address
HARVEST_BASE_COLLECTOR_PROXY=0x7332051C4EeD9CD40B28BA0a1c5d042666897dA8

# step 2: deploy new Infrared imp (note, upgrade and initialize are protected by onlyGov)
forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
    --sig "deployInfraredImp()" \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY --verify \
    --broadcast
# todo: capture returned imp address
INFRAREDV1_7_IMP=0x8D5A82DdC916a2750fa9769Aae354BF7a19360B9

# step 3: upgrade infrared and initialize
# function upgradeInfrared(
#         bool _send,
#         address _infraredProxy,
#         address newInfraredImp,
#         address proxyAddr
#     ) external

# # first pass simulate
# forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
#     --sig "upgradeInfrared(bool,address,address,address)" false $INFRARED $INFRAREDV1_7_IMP $HARVEST_BASE_COLLECTOR_PROXY \
#     --rpc-url $RPC_URL -vvvv #\
#     # --private-key $PRIVATE_KEY 

# second pass execute
forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
    --sig "upgradeInfrared(bool,address,address,address)" true $INFRARED $INFRAREDV1_7_IMP $HARVEST_BASE_COLLECTOR_PROXY \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY 

# forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
#     --sig "validate()" \
#     --rpc-url $RPC_URL -vvvv


# forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
#     --sig "run(bool,address,address,address,address,address,uint256)" false $INFRARED $KEEPER $IBGT $WBERA $RECEIVOR $PAYOUT_AMOUNT \
#     --rpc-url $RPC_URL -vvvv #\
#     # --private-key $PRIVATE_KEY --verfiy -vvvv 


# forge script script/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
#     --sig "validate()" \
#     --rpc-url $RPC_URL -vvvv #\
#     --private-key $PRIVATE_KEY --verfiy -vvvv \
#     --broadcast 
