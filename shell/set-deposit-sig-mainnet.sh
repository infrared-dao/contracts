set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="http://35.203.86.197:8545/"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
IBERA="0x9b6761bf2397Bb5a6624a856cC84A3A14Dcd3fe5"
SIG="0xa6dff02f89c3951637e00ca67db8dc0aec209f13022a9d5fc402567acd4eb010d89ef118accb2eb87284f4ccd6da87791053f65ce6be60856e989cabfe39809ef2fa66939fd6cd5410eca551b32140d218d8f334125f37890df7df2c38246d10"
PUBKEY="0x928d6f66bfd9cb1ef18da6843ad9db6c1b6ec7e3093705c95224e8f20232f243e7a627d09144360d4c1775d8fafdb0e7"


forge script script/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "setDepositSignature(address,address,bytes,bytes)" $SAFE $IBERA $PUBKEY $SIG \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast 
