#!/bin/bash

source .env

# URL to retrieve the JSON from
URL="${BEACON_RPC}/eth/v1/beacon/headers/head"

# File to save the extracted message data
OUTPUT_FILE="data/beacon_block_header.json"

# File to save the extracted "data" from the second query
OUTPUT_FILE_2="data/beacon_state_raw.ssz"

# Step 1: Retrieve the first JSON and extract "message" and "state_root"
RESPONSE=$(curl -s $URL)

# Extract "message" and save it to the first output file
echo "$RESPONSE" | jq '.data[0].header.message' > $OUTPUT_FILE

# Use curl to get the JSON and pipe it to jq to extract the "message" key data
# curl -s $URL | jq '.data[0].header.message' > $OUTPUT_FILE

echo "Message data saved to $OUTPUT_FILE"

# Extract "state_root" for the next query
STATE_ROOT=$(echo "$RESPONSE" | jq -r '.data[0].header.message.state_root')
echo "Extracted state_root: $STATE_ROOT"

# Step 2: Make another request using "state_root" as a query parameter
SECOND_URL="${BEACON_RPC}/eth/v2/debug/beacon/states/${STATE_ROOT}"

# Get the second SSZ using the state_root
# SECOND_RESPONSE=$(curl -s $SECOND_URL)
curl -X GET --header 'Accept: application/octet-stream' -s $SECOND_URL -o $OUTPUT_FILE_2

# Extract "data" from the second JSON and save it to the second output file
# echo "$SECOND_RESPONSE" | jq '.data' > $OUTPUT_FILE_2
echo "State data saved to $OUTPUT_FILE_2"

