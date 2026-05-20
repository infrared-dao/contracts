set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://rpc.berachain.com"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"
INFRARED="0xb71b3DaEA39012Fb0f2B14D2a9C86da9292fC126"

# Figment
# PUBKEY="0x8007e88a66ad54839375b012eb602b798b59a507dc78dc966040458553de82c0fce583932121d539ae00ae73f5ed54e8"

# StakeLabs2
# PUBKEY="0x84d0f5ed328e029f104f7a3bb5778d188b2197415119b95a9719be47fd0e16e3fbda08dbf5bdfde0a7dab95db1807e47"

# A41
# PUBKEY="0x90d64ab2a8ab9b5faace9225d205d47dc0b8155592b354b860134928f7f39f15f54d909dad7897868aba6dc7e7eef6c8"

# Informal
# PUBKEY=0x86888df491e8ccdc5bb940b9dda51fa7449518593820c9e4e9033a7b87f5e9f8debbba6a4f68218711896906ad40ce71

# Stakelabs 1
# PUBKEY=0x88be126bfda4eee190e6c01a224272ed706424851e203791c7279aeecb6b503059901db35b1821f1efe4e6b445f5cc9f

forge script script/gov/InfraredMultisigGovernance.s.sol:InfraredMultisigGovernance \
    --sig "removeValidator(address,address,bytes)" $SAFE $INFRARED $PUBKEY \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --ffi \
    --broadcast -vvvv
