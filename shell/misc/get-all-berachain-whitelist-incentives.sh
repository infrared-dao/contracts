set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

WHITELIST="true"

# TOKENS=()
# Initialize empty array for tokens
declare -a TOKENS=()
declare -A SEEN_TOKENS  # Associative array to track seen tokens

# Get reward vault factory address
echo "Fetching reward vault factory address from $INFRARED"
REWARD_VAULT_FACTORY=$(cast call --rpc-url $RPC_URL $INFRARED "rewardsFactory()(address)") || {
    echo "Error: Failed to get rewards factory address"
    exit 1
}

echo "Reward vault factory address: $REWARD_VAULT_FACTORY"
echo "Fetching all vaults length"
ALL_VAULTS_LENGTH=$(cast call --rpc-url $RPC_URL $REWARD_VAULT_FACTORY "allVaultsLength()(uint256)")  || {
    echo "Error: Failed to get all vaults"
    exit 1
}
echo "Number of vaults: $ALL_VAULTS_LENGTH"

# Check if there are any vaults
if [ "$ALL_VAULTS_LENGTH" -eq 0 ]; then
    echo "No vaults found"
    exit 0
fi

for i in $(seq 0 $((ALL_VAULTS_LENGTH - 1))); do
    echo "Processing vault at index $i"

    REWARD_VAULT=$(cast call --rpc-url $RPC_URL $REWARD_VAULT_FACTORY "allVaults(uint256)(address)" $i) || {
        echo "Error: Failed to get reward vault"
        continue
    }
    echo "Reward vault address: $REWARD_VAULT"
    INCENTIVE_TOKENS=$(cast call --rpc-url $RPC_URL $REWARD_VAULT "getWhitelistedTokens()(address[])")  || {
        echo "Error: Failed to get incentive tokens for vault $REWARD_VAULT"
        continue
    }
    echo "Raw incentive tokens: $INCENTIVE_TOKENS"
    # TOKENS+=$INCENTIVE_TOKENS
    # Process tokens if not empty and not just empty array "[]"
    if [ -n "$INCENTIVE_TOKENS" ] && [ "$INCENTIVE_TOKENS" != "[]" ]; then
        # Remove square brackets and split by comma
        # Convert "[addr1,addr2,addr3]" to "addr1 addr2 addr3"
        CLEANED_TOKENS=$(echo "$INCENTIVE_TOKENS" | tr -d '[]' | tr ',' ' ')
        echo "Cleaned tokens: $CLEANED_TOKENS"
        
        # Convert to array
        read -r -a TEMP_TOKENS <<< "$CLEANED_TOKENS"
        
        # Add only unique tokens
        for token in "${TEMP_TOKENS[@]}"; do
            # Check if token exists in SEEN_TOKENS (empty if not seen)
            # if [[ ! ${SEEN_TOKENS["$token"]} ]]; then
            if [[ -z "${SEEN_TOKENS[$token]+x}" ]]; then
                SEEN_TOKENS["$token"]=1
                TOKENS+=("$token")
                echo "Added new unique token: $token"
            fi
        done
    fi
done

IFS=, TOKENS_STR="${TOKENS[*]}"

echo $TOKENS_STR
