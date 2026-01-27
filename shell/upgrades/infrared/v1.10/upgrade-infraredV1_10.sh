set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
INFRARED="0xb71b3DaEa39012Fb0f2B14D2a9C86da9292fC126"
KEEPER=0x3e08c3728A69Ab3804Af74F55f500CEedb342Ac7
IBGT=0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
IR_TOKEN=0xa1B644AEC990Ad6023811cED36E6A2d6D128C7C9
# IR_TOKEN=0xc7dC2a8edAE1e5a321658B507148e70b5eeC7379 # dummy IR for testing
PAYOUT_AMOUNT=10000000000000000000 # 10 IR tokens (10e18)

STAKED_IR=0xb5E9cfD2751363F38a696626C18DB4aFf7512756

RPC_URL="https://rpc.berachain.com"

# forge clean

# FOUNDRY_PROFILE=production forge build --sizes

# function upgradeInfrared(
#     bool _send,
#     address _infraredProxy,
#     address _irToken,
#     address _ibgt,
#     address _keeper,
#     uint256 _payoutAmount,
#     uint256 _minIBGTAllocation
# )

# dry run
# FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
#     --sig "upgradeInfrared(bool,address,address,address,address,address,uint256)" \
#     "false" $INFRARED $IR_TOKEN $IBGT $KEEPER $STAKED_IR $PAYOUT_AMOUNT \
#     --fork-url $RPC_URL -vvvv

# live
FOUNDRY_PROFILE=production forge script script/upgrades/infrared/v1.10/UpgradeInfraredV1_10.s.sol:UpgradeInfraredV1_10 \
    --sig "upgradeInfrared(bool,address,address,address,address,address,uint256)" \
    "true" $INFRARED $IR_TOKEN $IBGT $KEEPER $STAKED_IR $PAYOUT_AMOUNT \
    --rpc-url $RPC_URL -vvvv \
    --private-key $PRIVATE_KEY --verify \
    --broadcast
