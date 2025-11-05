#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
# RPC_URL="https://rpc.berachain.com"
RPC_URL="https://rpc.berachain.com"
SCRIPT="script/keeper/InfraredKeeperScript.s.sol:InfraredKeeperScript"
SAFE="0x242D55c9404E0Ed1fD37dB1f00D60437820fe4f0"