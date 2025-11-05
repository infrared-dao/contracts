set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

# Figment
# PUBKEY="0x8007e88a66ad54839375b012eb602b798b59a507dc78dc966040458553de82c0fce583932121d539ae00ae73f5ed54e8"

# StakeLabs2
PUBKEY="0x84d0f5ed328e029f104f7a3bb5778d188b2197415119b95a9719be47fd0e16e3fbda08dbf5bdfde0a7dab95db1807e47"

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "removeValidator(address,address,bytes)" $SAFE $INFRARED $PUBKEY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
