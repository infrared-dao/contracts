set -euo pipefail

# expect PRIVATE_KEY in `.env`
source .env

RPC_URL="https://bepolia.rpc.berachain.com"

WITHDRAWOR=0x901528D1c588662FF75b19Ade33618115131dA84
IBERA=0x7292B549F9F59fC22bABCD7b6706e7D6889C2624
DEPOSITOR=0x51761dC3fFB5B54186a70ef1d55c44153671D1FF
INFRARED=0xb4fe1c9a7068586f377eCaD40632347be2372E6C

PUBKEY=0x9283049422ea550a11d60e9c6670ffda19e30fae59b722b8657e0911ed2f6dbbf7c8d2d8e7821b4a222d1af2fe1399a1
CREDENTIALS=0x010000000000000000000000901528d1c588662ff75b19ade33618115131da84
SIGNATURE=0x945b9596ac09b2c9f1afe652b25524ffcfa26abe696a8ece1edc91aae6618cd03c05e76369680f79a6ee0c2ecb401e6919c38cb9dfa09cf1764a59129bd3326af267aaa4ded5d7342dfc9ce817cf387dd7ef9ba1757c667d69ece9d82bb5915c
ADDR=0xA3A771A7c4AFA7f0a3f88Cc6512542241851C926

# register validator on infarred
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $INFRARED "addValidators((bytes,address)[])" "[(${PUBKEY}, ${ADDR})]"

# set init 10k deposit sig
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $IBERA "setDepositSignature(bytes,bytes)" $PUBKEY $SIGNATURE

# deposit into ibera (10k)
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $IBERA "mint(address)" $ADDR --value 10000000000000000000000

# init CL deposit
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $DEPOSITOR "executeInitialDeposit(bytes)" $PUBKEY

# set commission
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $INFRARED "queueValCommission(bytes,uint96)" $PUBKEY 10000

# set min activation deposit
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $DEPOSITOR "setMinActivationDeposit(uint256)" 250000000000000000000000

# more deposits
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $IBERA "mint(address)" $ADDR --value 250000000000000000000000

# -----------------
# 
# withdraw
cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $IBERA "burn(address,uint256)" $ADDR 500000000000000000000

cast send --private-key $PRIVATE_KEY --rpc-url $RPC_URL $IBERA "burn(address,uint256)" $ADDR 4496730000000000000000

cast call --rpc-url $RPC_URL $WITHDRAWOR "requests(uint256)" 1
cast call --rpc-url $RPC_URL $WITHDRAWOR "getQueuedAmount()(uint256)"

cast call --rpc-url $RPC_URL $IBERA "stakes(bytes)" $PUBKEY

