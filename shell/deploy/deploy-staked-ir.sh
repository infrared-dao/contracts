set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
IR_TOKEN=0xa1B644AEC990Ad6023811cED36E6A2d6D128C7C9
# IR_TOKEN=0xc7dC2a8edAE1e5a321658B507148e70b5eeC7379 # dummy IR for testing

RPC_URL="https://rpc.berachain.com"

forge clean

FOUNDRY_PROFILE=production forge build --sizes

# dry run
FOUNDRY_PROFILE=production forge script script/deploy/DeployStakedIR.s.sol:DeployStakedIR \
    --sig "deployStakedIR(address)" \
    $IR_TOKEN \
    --fork-url $RPC_URL -vvvv --private-key $PRIVATE_KEY

# live
# FOUNDRY_PROFILE=production forge script script/deploy/DeployStakedIR.s.sol:DeployStakedIR \
#     --sig "deployStakedIR(address)" \
#     $IR_TOKEN \
#     --rpc-url $RPC_URL -vvvv \
#     --private-key $PRIVATE_KEY --verify \
#     --broadcast
