#!/usr/bin/env bash
set -euo pipefail

# Load environment variables
source .env

# Common variables
RPC_URL="http://35.203.86.197:8545/"
SCRIPT="script/InfraredKeeperScript.s.sol:InfraredKeeperScript"
SAFE="0x182a31A27A0D39d735b31e80534CFE1fCd92c38f"