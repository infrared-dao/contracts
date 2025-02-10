set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="http://35.203.86.197:8545/"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"
ADDR="0x36f159e20F1e53b915BDf6b108B43B8D1CdE0407"
PUBKEY="0x928d6f66bfd9cb1ef18da6843ad9db6c1b6ec7e3093705c95224e8f20232f243e7a627d09144360d4c1775d8fafdb0e7"

# ADDR=""
# PUBKEY="0x928d6f66bfd9cb1ef18da6843ad9db6c1b6ec7e3093705c95224e8f20232f243e7a627d09144360d4c1775d8fafdb0e7"

forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "addValidator(address,address,address,bytes)" $SAFE $INFRARED $ADDR $PUBKEY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
