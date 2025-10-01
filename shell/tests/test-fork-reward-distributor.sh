set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

#  RPC URL
FORK_RPC_URL="https://rpc.berachain.com"
RPC_URL="http://127.0.0.1:8545"

# fork anvil in background
echo "Starting Anvil fork..."
nohup anvil -f $FORK_RPC_URL > anvil.log 2>&1 &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 10  
echo "Anvil fork started with PID: $ANVIL_PID"

# deploy new implementation
echo "Deploying reward distributor"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
STAKING_TOKEN=0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8
REWARD_TOKEN=0x334404782aB67b4F6B2A619873E579E971f9AAB7

DEPLOY_OUTPUT=$(forge script script/DeployRewardDistributor.s.sol:DeployRewardDistributor --sig "run(address,address,address,address)" $SAFE $INFRARED $STAKING_TOKEN $REWARD_TOKEN --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv 2>&1)
REWARD_DIST=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=new RewardDistributor@)0x[a-fA-F0-9]{40}' | head -n1)

echo "Extracted Address: $REWARD_DIST"
# if [[ -z "$REWARD_DIST" ]]; then
#     echo "Error: Failed to extract deployment address!"
#     kill "$ANVIL_PID"
#     exit 1

# REWARD_DIST=$(echo "$REWARD_DIST" | tr -d '\n' | tr -d '\r')

echo "Reward distributor: $REWARD_DIST"

# tests
# multisig acc with 25k wBYUSD
ACCOUNT=0x4D6aC3194a3b9c4eC13501dC686B920d7930BCc3
cast rpc anvil_impersonateAccount $ACCOUNT
cast send $REWARD_TOKEN \
    --rpc-url $RPC_URL \
    --from $ACCOUNT \
    "transfer(address,uint256)(bool)" \
    $REWARD_DIST \
    25000000000000000000000 \
    --unlocked \
    -vvvv

cast call --rpc-url $RPC_URL --trace $REWARD_DIST "getExpectedAmount()(uint256)"

cast call --rpc-url $RPC_URL --trace $REWARD_DIST "getMaxTotalSupply()(uint256)"

MAX_SUPPLY=$(cast call --rpc-url $RPC_URL $REWARD_DIST "getMaxTotalSupply()(uint256)" | awk '{print $1}')

cast rpc anvil_stopImpersonatingAccount $ACCOUNT
cast rpc anvil_impersonateAccount $SAFE

cast send $REWARD_DIST \
    --rpc-url $RPC_URL \
    --from $SAFE \
    "distribute(uint256)" \
    $MAX_SUPPLY \
    --unlocked \
    -vvvv

# Cleanup: Kill Anvil process
echo "Shutting down Anvil..."
kill "$ANVIL_PID"
echo "Anvil stopped."