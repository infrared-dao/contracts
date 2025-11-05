set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

#  RPC URL
FORK_RPC_URL="https://bepolia.rpc.berachain.com"
RPC_URL="http://127.0.0.1:8545"

# fork anvil in background
echo "Starting Anvil fork..."
nohup anvil -f $FORK_RPC_URL > anvil.log 2>&1 &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 10  
echo "Anvil fork started with PID: $ANVIL_PID"

# deploy new implementation
echo "Deploying iBERAv2..."
WITHDRAWOR_LITE=0x901528D1c588662FF75b19Ade33618115131dA84
WITHDRAW_CONTRACT=0x00000961Ef480Eb55e80D19ad83579A64c007002
DEPLOY_OUTPUT=$(forge script script/upgrades/staking/UpgradeInfraredBERAWithdrawor.s.sol:UpgradeInfraredBERAWithdrawor --sig "run(address,address)" $WITHDRAWOR_LITE $WITHDRAW_CONTRACT  --broadcast  --rpc-url $RPC_URL  --private-key $PRIVATE_KEY -vvvv 2>&1)
IBERA_WITHDRAWOR_IMPLEMENTATION=$(echo "$DEPLOY_OUTPUT" | grep -oP '(?<=new InfraredBERAWithdrawor@)0x[a-fA-F0-9]{40}' | head -n1)

echo "Extracted Address: $IBERA_WITHDRAWOR_IMPLEMENTATION"
if [[ -z "$IBERA_WITHDRAWOR_IMPLEMENTATION" ]]; then
    echo "Error: Failed to extract deployment address!"
    kill "$ANVIL_PID"
    exit 1
fi
IBERA_WITHDRAWOR_IMPLEMENTATION=$(echo "$IBERA_WITHDRAWOR_IMPLEMENTATION" | tr -d '\n' | tr -d '\r')

echo "IBERA withdrawor deployed at: $IBERA_WITHDRAWOR_IMPLEMENTATION"

# tests
# test withdrawal
export WITHDRAW_AMOUNT_ETH=10000
export WITHDRAW_AMOUNT_GWEI=${WITHDRAW_AMOUNT_ETH}000000000
export COMETBFT_PUB_KEY=0x957004733f0c4d7e51b4f1ac3f1c08247f9c5455d302b669c723eb80d8c286515b5623757a9053a5a7b8c17ee3feed4b
export WITHDRAW_CREDENTIAL_PRIVATE_KEY=0xd208b29df6c1bac0a778be73620d323dd4cdff77cac773385bd4c13e25aebef9
WITHDRAW_FEE_HEX=$(cast call -r $RPC_URL $WITHDRAW_CONTRACT);
WITHDRAW_FEE=$(cast to-dec $WITHDRAW_FEE_HEX);
echo $WITHDRAW_FEE; 
WITHDRAW_REQUEST=$(cast abi-encode --packed '(bytes,uint64)' $COMETBFT_PUB_KEY $WITHDRAW_AMOUNT_GWEI);
echo $WITHDRAW_REQUEST;
cast call --trace $WITHDRAW_CONTRACT $WITHDRAW_REQUEST --rpc-url $RPC_URL --private-key $WITHDRAW_CREDENTIAL_PRIVATE_KEY --value ${WITHDRAW_FEE}wei;
# cast send $WITHDRAW_CONTRACT $WITHDRAW_REQUEST --rpc-url $RPC --private-key $WITHDRAW_CREDENTIAL_PRIVATE_KEY --value ${WITHDRAW_FEE}wei;

# Cleanup: Kill Anvil process
echo "Shutting down Anvil..."
kill "$ANVIL_PID"
echo "Anvil stopped."