set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# RPC_URL="https://rpc.berachain.com"
RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

DURATION=3600
IBGT="0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b" # IBGT
HONEY="0xFCBD14DC51f0A4d49d5E53C2E0950e0bC26d0Dce"
WBERA="0x6969696969696969696969696969696969696969"
BYUSD="0x688e72142674041f8f6Af4c808a4045cA1D6aC82"
BYUSDHONEYLP="0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8"

STAKING_TOKEN=$IBGT
REWARD_TOKEN=$IBGT

# updateRewardsDurationForVault(
#         address safe,
#         address payable infrared,
#         address _stakingToken,
#         address _rewardsToken,
#         uint256 _rewardsDuration


forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "updateRewardsDurationForVault(address,address,address,address,uint256)" $SAFE $INFRARED $STAKING_TOKEN $REWARD_TOKEN $DURATION \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv


