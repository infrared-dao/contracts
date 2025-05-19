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
echo "Deploying InfraredV4..."
DEPLOY_OUTPUT=$(forge script script/DeployInfraredV1_5.s.sol:DeployInfraredV1_5  --broadcast  --rpc-url $RPC_URL  --private-key $PRIVATE_KEY -vvvv 2>&1)
INFRARED_V5_IMPLEMENTATION=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=new InfraredV1_5@)0x[a-fA-F0-9]{40}' | head -n1)

echo "Extracted Address: $INFRARED_V4_IMPLEMENTATION"
if [[ -z "$INFRARED_V5_IMPLEMENTATION" ]]; then
    echo "Error: Failed to extract deployment address!"
    kill "$ANVIL_PID"
    exit 1
fi
INFRARED_V5_IMPLEMENTATION=$(echo "$INFRARED_V5_IMPLEMENTATION" | tr -d '\n' | tr -d '\r')

echo "InfraredV5 deployed at: $INFRARED_V5_IMPLEMENTATION"

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

# this cannot be broadcast for test as it sends batched script to multisig UI for signing
echo "Preparing to upgrade Infrared contract..."
forge script script/UpgradeInfraredV1_5.s.sol:UpgradeInfraredV1_5 \
    --sig "run(address,address,address)" $SAFE $INFRARED "$INFRARED_V5_IMPLEMENTATION" \
    --rpc-url $RPC_URL -vvvv

# Cleanup: Kill Anvil process
echo "Shutting down Anvil..."
kill "$ANVIL_PID"
echo "Anvil stopped."