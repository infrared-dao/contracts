set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://bepolia.rpc.berachain.com"

WITHDRAWOR_LITE=0x901528D1c588662FF75b19Ade33618115131dA84
WITHDRAW_PRECOMPILE=0x00000961Ef480Eb55e80D19ad83579A64c007002
IBERA=0x7292B549F9F59fC22bABCD7b6706e7D6889C2624
DEPOSITOR=0x51761dC3fFB5B54186a70ef1d55c44153671D1FF

forge script script/upgrades/staking/UpgradeInfraredBERATestnet.s.sol:UpgradeInfraredBERATestnet \
    --sig "run(address,address,address,address)" $WITHDRAWOR_LITE $WITHDRAW_PRECOMPILE $IBERA $DEPOSITOR \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY -vvvv
