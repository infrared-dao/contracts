set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
SAFE_TX_SERVICE="https://transaction-mainnet.safe.berachain.com/"

RPC_URL="https://rpc.berachain.com"

# sugested values. feel free to change

FEE_DIVISOR_SHAREHOLDERS=10 # 10 = 10%, 2=50%, 5=20% ...
OPERATOR_WEIGHT=500000 # numerator of 1e6 for weight of operator rewards going back to operators. The rest goes to ibgt vault. 5e5 = 80%
HARVEST_OPERATOR_FEE_RATE=100000 # numerator of 1e6 for fee on operator rewards 1e5 = 10%
HARVEST_VAULT_FEE_RATE=100000 # numerator of 1e6 for fee on vault rewards 1e5 = 10%
HARVEST_BRIBES_FEE_RATE=50000 # numerator of 1e6 for fee on bribes rewards 1e5 = 10%
HARVEST_BOOST_FEE_RATE=50000 # numerator of 1e6 for fee on boost rewards 1e5 = 10%

# uint16 feeDivisorShareholders, uint256 operatorWeight, uint256 harvestOperatorFeeRate, uint256 harvestVaultFeeRate, uint256 harvestBribesFeeRate, uint256 harvestBoostFeeRate

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setFees(address,address,address,uint16,uint256,uint256,uint256,uint256,uint256)" $SAFE $INFRARED $IBERA $FEE_DIVISOR_SHAREHOLDERS $OPERATOR_WEIGHT $HARVEST_OPERATOR_FEE_RATE $HARVEST_VAULT_FEE_RATE $HARVEST_BRIBES_FEE_RATE $HARVEST_BOOST_FEE_RATE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
