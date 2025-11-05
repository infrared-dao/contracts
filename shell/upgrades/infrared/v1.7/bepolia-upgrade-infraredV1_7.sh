set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED=0xb4fe1c9a7068586f377eCaD40632347be2372E6C
KEEPER=0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926
IBGT=0xe3115eb91E03Aee24b4531E80CEA2C90757e1B88
WBERA=0x6969696969696969696969696969696969696969
RECEIVOR=0xF5740E876bE3902cA727306d0817b86DfDE00908

PAYOUT_AMOUNT=10000000000000000000

RPC_URL="https://bepolia.rpc.berachain.com"

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
forge script script/upgrades/infrared/v1.7/UpgradeInfraredTestnetV1_7.s.sol:UpgradeInfraredTestnetV1_7 \
    --sig "deployCollector(address,address,address,address,address,uint256)" $INFRARED $KEEPER $IBGT $WBERA $RECEIVOR $PAYOUT_AMOUNT \
    --rpc-url $RPC_URL -vvvv --sender $KEEPER \
    --private-key $PRIVATE_KEY --verify \
    --broadcast
# todo: capture returned proxy address
HARVEST_BASE_COLLECTOR_PROXY=0xe6f6E4A3D7c64DacE2b048f80d8FF9Cea0b4990f

# step 2: deploy new Infrared imp (note, upgrade and initialize are protected by onlyGov)
forge script script/upgrades/infrared/v1.7/UpgradeInfraredTestnetV1_7.s.sol:UpgradeInfraredTestnetV1_7 \
    --sig "deployInfraredImp()" \
    --rpc-url $RPC_URL -vvvv --sender $KEEPER \
    --private-key $PRIVATE_KEY --verify \
    --broadcast
# todo: capture returned imp address
INFRAREDV1_7_IMP=0xAd3b4FFf6b40712326B7b04E104a87efb8BfB895

# step 3: upgrade infrared and initialize
# function upgradeInfrared(
#         bool _send,
#         address _infraredProxy,
#         address newInfraredImp,
#         address proxyAddr
#     ) external

forge script script/upgrades/infrared/v1.7/UpgradeInfraredTestnetV1_7.s.sol:UpgradeInfraredTestnetV1_7 \
    --sig "upgradeInfrared(address,address,address)" $INFRARED $INFRAREDV1_7_IMP $HARVEST_BASE_COLLECTOR_PROXY \
    --rpc-url $RPC_URL -vvvv --sender $KEEPER \
    --private-key $PRIVATE_KEY \
    --broadcast
