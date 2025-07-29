set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"

RPC_URL="https://rpc.berachain.com"


# enum FeeType {
#     HarvestOperatorFeeRate,
#     HarvestOperatorProtocolRate,
#     HarvestVaultFeeRate,
#     HarvestVaultProtocolRate,
#     HarvestBribesFeeRate,
#     HarvestBribesProtocolRate,
#     HarvestBoostFeeRate,
#     HarvestBoostProtocolRate
# }

FEE_TYPE=2  # pick from above (uint8 index starting at 0 = HarvestOperatorFeeRate)
FEE_AMOUNT=10000  # 1% = 1e4

# uint16 feeDivisorShareholders, uint256 operatorWeight, uint256 harvestOperatorFeeRate, uint256 harvestVaultFeeRate, uint256 harvestBribesFeeRate, uint256 harvestBoostFeeRate

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "updateFee(address,address,uint8,uint256)" $SAFE $INFRARED $FEE_TYPE $FEE_AMOUNT \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
