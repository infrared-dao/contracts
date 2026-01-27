set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

# STAKING_ASSET=0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8
VAULT=0xbbB228B0D7D83F86e23a5eF3B1007D0100581613
TO=0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0
TOKEN="0x688e72142674041f8f6Af4c808a4045cA1D6aC82"
AMOUNT=6077393474

# function recoverERC20FromVault(
#   address safe,
#   address payable infrared,
#   address _vault,
#   address _to,
#   address _token,
#   uint256 _amount

# forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
#     --sig "recoverERC20FromOldVault(bool,address,address,address,address,address,uint256)" "false" $SAFE $INFRARED $VAULT $TO $TOKEN $AMOUNT  \
#     --fork-url $RPC_URL \
#     --sender 0x1eCF087ea1194AB182A53De849d61deB917D733F --unlocked \
#     -vvvv

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "recoverERC20FromOldVault(bool,address,address,address,address,address,uint256)" "true" $SAFE $INFRARED $VAULT $TO $TOKEN $AMOUNT  \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    -vvvv