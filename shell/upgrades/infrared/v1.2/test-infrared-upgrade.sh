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
echo "Deploying InfraredV2..."
DEPLOY_OUTPUT=$(forge script script/upgrades/infrared/v1.2/DeployInfraredV2.s.sol:DeployInfraredV2  --broadcast  --rpc-url $RPC_URL  --private-key $PRIVATE_KEY -vvvv 2>&1)
INFRARED_V2_IMPLEMENTATION=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=new InfraredV2@)0x[a-fA-F0-9]{40}' | head -n1)

echo "Extracted Address: $INFRARED_V2_IMPLEMENTATION"
if [[ -z "$INFRARED_V2_IMPLEMENTATION" ]]; then
    echo "Error: Failed to extract deployment address!"
    kill "$ANVIL_PID"
    exit 1
fi
INFRARED_V2_IMPLEMENTATION=$(echo "$INFRARED_V2_IMPLEMENTATION" | tr -d '\n' | tr -d '\r')

echo "InfraredV2 deployed at: $INFRARED_V2_IMPLEMENTATION"

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

STAKING_TOKENS=(
    "0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"  # IBGT
    "0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4"  # (50WETH-50WBERA-WEIGHTED)
    "0xF961a8f6d8c69E7321e78d254ecAfBcc3A637621"  # (USDC.e-HONEY-STABLE)
    "0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8"  # (BYUSD-HONEY-STABLE)
    "0x2c4a603A2aA5596287A06886862dc29d56DbC354"  # (50WBERA-50HONEY-WEIGHTED)
    "0x38fdD999Fe8783037dB1bBFE465759e312f2d809"  # (50WBTC-50WBERA-WEIGHTED)
)

IFS=, STAKING_TOKENS_STR="${STAKING_TOKENS[*]}"

# this cannot be broadcast for test as it sends batched script to multisig UI for signing
echo "Preparing to upgrade Infrared contract..."
forge script script/UpgradeInfrared.s.sol:UpgradeInfrared \
    --sig "run(address,address,address,address[])" $SAFE $INFRARED "$INFRARED_V2_IMPLEMENTATION" "[$STAKING_TOKENS_STR]" \
    --rpc-url $RPC_URL -vvvv

# Cleanup: Kill Anvil process
echo "Shutting down Anvil..."
kill "$ANVIL_PID"
echo "Anvil stopped."