set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

# Change these to correct params
ADMIN_ADDRESS="0x94092182D03fE8517A0345c455caA8047f9feb5b"
VOTING_KEEPER="0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926"
REWARDS_DURATION=2592000
BRIBE_COLLECTOR_PAYOUT_AMOUNT=1000000000000000000

# Berachain deployments
BGT="0x289274787bAF083C15A45a174b7a8e44F0720660"
BERACHAIN_REWARDS_FACTORY="0xE2257F3C674a7CBBFFCf7C01925D5bcB85ea0367"
BERA_CHEF="0x2C2F301f380dDc9c36c206DC3df8EA8688419cC1"
BEACON_DEPOSIT="0x4242424242424242424242424242424242424242"
WBERA="0x2C2F301f380dDc9c36c206DC3df8EA8688419cC1"
HONEY="0xd137593CDB341CcC78426c54Fb98435C60Da193c"

# Cartio RPC URL
RPC_URL="https://bartio.rpc.berachain.com"

# VERIFYER_URL='https://api.routescan.io/v2/network/testnet/evm/80000/etherscan'

forge script script/InfraredMultisigDeployer.s.sol:InfraredMultisigDeployer \
    --sig "run(address,address,address,address,address,address,address,address,uint256,uint256)" $ADMIN_ADDRESS $VOTING_KEEPER $BGT $BERACHAIN_REWARDS_FACTORY $BERA_CHEF $BEACON_DEPOSIT $WBERA $HONEY $REWARDS_DURATION $BRIBE_COLLECTOR_PAYOUT_AMOUNT \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --skip-simulation \
    --ffi \
    --broadcast 
    # --verify \
    # --verifier-url $VERIFYER_URL \
    # --etherscan-api-key "verifyContract" \
    
    
