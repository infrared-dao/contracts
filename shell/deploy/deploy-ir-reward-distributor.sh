set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
# IR_TOKEN=0xa1B644AEC990Ad6023811cED36E6A2d6D128C7C9
IBGT=0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b
IR_TOKEN=$IBGT # use iBGT for experimental distributions
INFRARED=0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126
MIN_IBGT_ALLOCATION=0 # 0% for ibgt distributor

RPC_URL="https://rpc.berachain.com"

forge clean

FOUNDRY_PROFILE=production forge build --sizes

# function deployDistributor(
#     address _infraredProxy,
#     address _irToken,
#     uint256 _minIBGTAllocation
# )

# dry run
FOUNDRY_PROFILE=production forge script script/deploy/DeployIRDistributor.s.sol:DeployDistributor \
    --sig "deployDistributor(address,address,uint256)" \
    $INFRARED $IR_TOKEN $MIN_IBGT_ALLOCATION \
    --fork-url $RPC_URL -vvvv --private-key $PRIVATE_KEY

# live
# FOUNDRY_PROFILE=production forge script script/deploy/DeployIRDistributor.s.sol:DeployDistributor \
#     --sig "deployDistributor(address,address,uint256)" \
#     $INFRARED $IR_TOKEN $MIN_IBGT_ALLOCATION \
#     --rpc-url $RPC_URL -vvvv \
#     --private-key $PRIVATE_KEY --verify \
#     --broadcast
