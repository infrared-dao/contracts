set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"

SAFE=0x182a31A27A0D39d735b31e80534CFE1fCd92c38f
WITHDRAWOR_LITE=0x8c0E122960dc2E97dc0059c07d6901Dce72818E1
WITHDRAW_PRECOMPILE=0x00000961Ef480Eb55e80D19ad83579A64c007002
IBERA=0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5
DEPOSITOR=0x04CddC538ea65908106416986aDaeCeFD4CAB7D7

# fill in from deployments
WITHDRAWOR_NEW=
DEPOSITOR_NEW=
IBERA_NEW=

FOUNDRY_PROFILE=production forge script script/upgrades/staking/UpgradeInfraredBERA.s.sol:UpgradeInfraredBERA \
    --sig "run(address,address,address,address,address,address,address,address)" $SAFE $WITHDRAWOR_LITE $WITHDRAW_PRECOMPILE $IBERA $DEPOSITOR $WITHDRAWOR_NEW $DEPOSITOR_NEW $IBERA_NEW  \
    --broadcast  --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY -vvvv
