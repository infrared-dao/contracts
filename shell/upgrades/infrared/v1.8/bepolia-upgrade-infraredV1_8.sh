set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED=0xb4fe1c9a7068586f377eCaD40632347be2372E6C
KEEPER=0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926
IBGT=0xe3115eb91E03Aee24b4531E80CEA2C90757e1B88
WBERA=0x6969696969696969696969696969696969696969
RECEIVOR=0xF5740E876bE3902cA727306d0817b86DfDE00908
BRIBE_COLLECTOR=0x609dF5AbC810aB14968B3f71ec7b3Cec4E892377

# PAYOUT_AMOUNT=1000000000000000000000
# PAYOUT_TOKEN=$IBGT

RPC_URL="https://bepolia.rpc.berachain.com"

forge clean

forge build --sizes


# deploy and upgrade bribe collector and infrared
# function upgradeInfraredTestnet(
#     address _bribeCollectorProxy,
#     address _infraredProxy,
# )

forge script script/upgrades/infrared/v1.8/UpgradeInfraredV1_8.s.sol:UpgradeInfraredV1_8 \
    --sig "upgradeInfraredTestnet(address,address)" $BRIBE_COLLECTOR $INFRARED \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY --verify --broadcast

