set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

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
echo "Deploying BribeCollectorV2..."
DEPLOY_OUTPUT=$(forge script script/upgrades/bribe-collector/v1.2/DeployBribeCollectorV1_2.s.sol:DeployBribeCollectorV1_2  --broadcast  --rpc-url $RPC_URL  --private-key $PRIVATE_KEY -vvvv 2>&1)
BRIBE_COLLECTOR_V2_IMPLEMENTATION=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=new BribeCollectorV1_2@)0x[a-fA-F0-9]{40}' | head -n1)

echo "Extracted Address: $BRIBE_COLLECTOR_V2_IMPLEMENTATION"
if [[ -z "$BRIBE_COLLECTOR_V2_IMPLEMENTATION" ]]; then
    echo "Error: Failed to extract deployment address!"
    kill "$ANVIL_PID"
    exit 1
fi
BRIBE_COLLECTOR_V2_IMPLEMENTATION=$(echo "$BRIBE_COLLECTOR_V2_IMPLEMENTATION" | tr -d '\n' | tr -d '\r')

echo "BribeCollectorV2 deployed at: $BRIBE_COLLECTOR_V2_IMPLEMENTATION"

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
BRIBE_COLLECTOR="0x8d44170e120B80a7E898bFba8cb26B01ad21298C"


# this cannot be broadcast for test as it sends batched script to multisig UI for signing
echo "Preparing to upgrade BribeCollector contract..."
forge script script/UpgradeBribeCollector.s.sol:UpgradeBribeCollector \
    --sig "run(address,address,address)" $SAFE $BRIBE_COLLECTOR "$BRIBE_COLLECTOR_V2_IMPLEMENTATION" \
    --rpc-url $RPC_URL -vvvv

# Cleanup: Kill Anvil process
echo "Shutting down Anvil..."
kill "$ANVIL_PID"
echo "Anvil stopped."