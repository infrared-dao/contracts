set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
KEEPER=0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7
IBGT=0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
WBERA=0x6969696969696969696969696969696969696969
RECEIVOR=0xf6a4A6aCECd5311327AE3866624486b6179fEF97

PAYOUT_AMOUNT=10000000000000000000000

FORK_RPC_URL="https://rpc.berachain.com"
RPC_URL="http://127.0.0.1:8545"

# fork anvil in background
echo "Starting Anvil fork..."
nohup anvil -f $FORK_RPC_URL > anvil.log 2>&1 &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 10  
echo "Anvil fork started with PID: $ANVIL_PID"

forge clean

forge build --sizes

# step 1: deploy new collector and proxy
echo "Deploying new collector and proxy ..."
# function deployCollector(
#         address _infraredProxy,
#         address _keeper,
#         address _ibgt,
#         address _wbera,
#         address _receivor,
#         uint256 _payoutAmount
#     ) external returns (address proxyAddr)
forge script script/upgrades/infrared/v1.7/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 --sig "deployCollector(address,address,address,address,address,uint256)" $INFRARED $KEEPER $IBGT $WBERA $RECEIVOR $PAYOUT_AMOUNT --rpc-url $RPC_URL -vvvv --private-key $PRIVATE_KEY --broadcast


# todo: capture returned proxy address
HARVEST_BASE_COLLECTOR_PROXY=0x79A3eE989b5641b72642f25784E92607D5172C97

# step 2: deploy new Infrared imp (note, upgrade and initialize are protected by onlyGov)
# deploy new implementation
echo "Deploying Infrared v1.7 ..."
DEPLOY_OUTPUT=$(forge script script/upgrades/infrared/v1.7/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7  --sig "deployInfraredImp()"  --rpc-url $RPC_URL -vvvv --private-key $PRIVATE_KEY --verfiy --broadcast 2>&1)
INFRAREDV1_7_IMP=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=new InfraredV1_7@)0x[a-fA-F0-9]{40}' | head -n1)

echo "Extracted Address: $INFRAREDV1_7_IMP"
if [[ -z "$INFRAREDV1_7_IMP" ]]; then
    echo "Error: Failed to extract deployment address!"
    kill "$ANVIL_PID"
    exit 1
fi
INFRAREDV1_7_IMP=$(echo "$INFRAREDV1_7_IMP" | tr -d '\n' | tr -d '\r')

echo "InfraredV1_7 deployed at: $INFRAREDV1_7_IMP"

INFRAREDV1_7_IMP=0x78B5ebb84Db848c55e553fe1928474F926d59D84

# step 3: upgrade infrared and initialize
# function upgradeInfrared(
#         bool _send,
#         address _infraredProxy,
#         address newInfraredImp,
#         address proxyAddr
#     ) external

# first pass simulate
echo "upgrading InfraredV1_7  ..."
forge script script/upgrades/infrared/v1.7/UpgradeInfraredV1_7.s.sol:UpgradeInfraredV1_7 \
    --sig "upgradeInfrared(bool,address,address,address)" false $INFRARED $INFRAREDV1_7_IMP $HARVEST_BASE_COLLECTOR_PROXY \
    --rpc-url $RPC_URL -vvvv #\
    # --private-key $PRIVATE_KEY 

echo "upgrade finished"

# Cleanup: Kill Anvil process
echo "Shutting down Anvil..."
kill "$ANVIL_PID"
echo "Anvil stopped."
