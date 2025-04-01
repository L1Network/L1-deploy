#!/bin/bash

# Set the API endpoint
API_URL="https://api.np.animus.is"

# Paths to the contract files
PROPOSALS_WASM="/data/bitcash-contract-dho/build/proposals.wasm"
PROPOSALS_ABI="/data/bitcash-contract-dho/build/proposals.abi"
REFERENDUMS_WASM="/data/bitcash-contract-dho/build/referendums.wasm"
REFERENDUMS_ABI="/data/bitcash-contract-dho/build/referendums.abi"

# Function to deploy a contract
deploy_contract() {
    local ACCOUNT=$1
    local WASM_FILE=$2
    local ABI_FILE=$3

    echo "Deploying contract to account: $ACCOUNT"
    cleos --url $API_URL set contract $ACCOUNT $(dirname $WASM_FILE) $(basename $WASM_FILE) $(basename $ABI_FILE) -p $ACCOUNT@active
    if [ $? -eq 0 ]; then
        echo "Successfully deployed contract to $ACCOUNT"
    else
        echo "Failed to deploy contract to $ACCOUNT"
        exit 1
    fi
}

# Prompt user to select which contract to deploy
echo "Select the contract to deploy:"
echo "1) Proposals (deploys to prop.bitcash)"
echo "2) Referendums (deploys to refe.bitcash)"
read -p "Enter the number of your choice: " choice

case $choice in
    1)
        deploy_contract "prop.bitcash" $PROPOSALS_WASM $PROPOSALS_ABI
        ;;
    2)
        deploy_contract "refe.bitcash" $REFERENDUMS_WASM $REFERENDUMS_ABI
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
