set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# RPC_URL="https://rpc.berachain.com"
RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

DURATION=600
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b" # IBGT
HONEY="0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce"

STAKING_TOKEN=$IBGT

# updateRewardsDurationForVault(
#         address safe,
#         address payable infrared,
#         address _stakingToken,
#         address _rewardsToken,
#         uint256 _rewardsDuration


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "updateRewardsDurationForVault(address,address,address,address,uint256)" $SAFE $INFRARED $STAKING_TOKEN $HONEY $DURATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 


