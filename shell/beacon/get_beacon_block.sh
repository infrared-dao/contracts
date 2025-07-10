#!/bin/bash

source .env

# URL to retrieve the JSON from
URL=$BEACON_RPC "/eth/v1/beacon/headers"

# File to save the extracted message data
OUTPUT_FILE="data/beacon_block_header.json"

# Use curl to get the JSON and pipe it to jq to extract the "message" key data
curl -s $URL | jq '.data[0].header.message' > $OUTPUT_FILE

echo "Message data saved to $OUTPUT_FILE"