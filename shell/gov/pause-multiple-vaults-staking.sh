set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

RPC_URL="https://rpc.berachain.com"

STAKING_TOKENS=(
    "0xac03CABA51e17c86c921E1f6CBFBdC91F8BB2E6b"  # IBGT
    "0xDd70A5eF7d8CfE5C5134b5f9874b09Fb5Ce812b4"  # (50WETH-50WBERA-WEIGHTED)
    "0xF961a8f6d8c69E7321e78d254ecAfBcc3A637621"  # (USDC.e-HONEY-STABLE)
    "0xdE04c469Ad658163e2a5E860a03A86B52f6FA8C8"  # (BYUSD-HONEY-STABLE)
    "0x2c4a603A2aA5596287A06886862dc29d56DbC354"  # (50WBERA-50HONEY-WEIGHTED)
    "0x38fdD999Fe8783037dB1bBFE465759e312f2d809"  # (50WBTC-50WBERA-WEIGHTED)
)

IFS=, STAKING_TOKENS_STR="${STAKING_TOKENS[*]}"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "pauseMultipleVaultStaking(address,address,address[])" $SAFE $INFRARED "[$STAKING_TOKENS_STR]" \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
