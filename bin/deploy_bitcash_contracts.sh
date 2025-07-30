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
        return 1
    fi
}

# Function to add eosio.code permission
add_eosio_code_permission() {
    local ACCOUNT=$1
    
    echo "Adding eosio.code permission to account: $ACCOUNT"
    cleos --url $API_URL set account permission $ACCOUNT active --add-code
    if [ $? -eq 0 ]; then
        echo "Successfully added eosio.code permission to $ACCOUNT"
    else
        echo "Failed to add eosio.code permission to $ACCOUNT"
        return 1
    fi
}

# Function to allow proposals contract to call referendums contract
setup_cross_contract_permission() {
    echo "Setting up cross-contract permission: Allow prop.bitcash to call refe.bitcash"
    
    # First, get the current active permission for refe.bitcash
    echo "Getting current permissions for refe.bitcash..."
    CURRENT_PERMISSION=$(cleos --url $API_URL get account refe.bitcash --json 2>/dev/null | jq -r '.permissions[] | select(.perm_name == "active") | .required_auth')
    
    if [ $? -ne 0 ] || [ -z "$CURRENT_PERMISSION" ]; then
        echo "Failed to get current permissions for refe.bitcash"
        return 1
    fi
    
    # Extract current keys, accounts, and threshold
    CURRENT_KEYS=$(echo $CURRENT_PERMISSION | jq '.keys')
    CURRENT_ACCOUNTS=$(echo $CURRENT_PERMISSION | jq '.accounts // []')
    CURRENT_THRESHOLD=$(echo $CURRENT_PERMISSION | jq '.threshold')
    
    echo "Current keys: $CURRENT_KEYS"
    echo "Current accounts: $CURRENT_ACCOUNTS"
    echo "Current threshold: $CURRENT_THRESHOLD"
    
    # Check if prop.bitcash permission already exists
    EXISTING_PROP=$(echo $CURRENT_ACCOUNTS | jq '.[] | select(.permission.actor == "prop.bitcash")')
    
    if [ -n "$EXISTING_PROP" ] && [ "$EXISTING_PROP" != "null" ]; then
        echo "prop.bitcash permission already exists. No changes needed."
        return 0
    fi
    
    # Add proposals contract permission to existing accounts
    NEW_ACCOUNTS=$(echo $CURRENT_ACCOUNTS | jq '. + [
        {
            permission: {
                actor: "prop.bitcash",
                permission: "active"
            },
            weight: 1
        }
    ]')
    
    # Create new permission structure that preserves everything and adds proposals contract
    NEW_PERMISSION=$(jq -n \
        --argjson threshold "$CURRENT_THRESHOLD" \
        --argjson keys "$CURRENT_KEYS" \
        --argjson accounts "$NEW_ACCOUNTS" \
        '{
            threshold: $threshold,
            keys: $keys,
            accounts: $accounts
        }')
    
    echo "Setting new permission for refe.bitcash..."
    echo "New permission structure:"
    echo "$NEW_PERMISSION" | jq '.'
    echo "$NEW_PERMISSION" > /tmp/referendums_permission.json
    
    cleos --url $API_URL set account permission refe.bitcash active /tmp/referendums_permission.json owner -p refe.bitcash@owner
    
    if [ $? -eq 0 ]; then
        echo "Successfully set cross-contract permission: prop.bitcash can now call refe.bitcash"
        echo "All existing permissions (including eosio.code) have been preserved."
        rm -f /tmp/referendums_permission.json
    else
        echo "Failed to set cross-contract permission"
        rm -f /tmp/referendums_permission.json
        return 1
    fi
}

# Function to display menu
show_menu() {
    echo "=== Bitcash Contract Deployment Menu ==="
    echo "1) Deploy Proposals contract (to prop.bitcash)"
    echo "2) Deploy Referendums contract (to refe.bitcash)"
    echo "3) Add eosio.code permission to prop.bitcash"
    echo "4) Add eosio.code permission to refe.bitcash"
    echo "5) Allow proposals contract to call referendums contract"
    echo "6) Deploy both contracts"
    echo "7) Setup both contracts (deploy + add permissions)"
    echo "8) Complete setup (deploy + permissions + cross-contract)"
    echo "0) Exit"
    echo "========================================"
}

# Main menu loop
main_menu() {
    while true; do
        show_menu
        read -p "Enter your choice [0-8]: " choice
        
        case $choice in
            1)
                deploy_contract "prop.bitcash" $PROPOSALS_WASM $PROPOSALS_ABI
                ;;
            2)
                deploy_contract "refe.bitcash" $REFERENDUMS_WASM $REFERENDUMS_ABI
                ;;
            3)
                add_eosio_code_permission "prop.bitcash"
                ;;
            4)
                add_eosio_code_permission "refe.bitcash"
                ;;
            5)
                setup_cross_contract_permission
                ;;
            6)
                echo "Deploying both contracts..."
                deploy_contract "prop.bitcash" $PROPOSALS_WASM $PROPOSALS_ABI
                deploy_contract "refe.bitcash" $REFERENDUMS_WASM $REFERENDUMS_ABI
                ;;
            7)
                echo "Setting up both contracts (deploy + permissions)..."
                deploy_contract "prop.bitcash" $PROPOSALS_WASM $PROPOSALS_ABI && \
                add_eosio_code_permission "prop.bitcash" && \
                deploy_contract "refe.bitcash" $REFERENDUMS_WASM $REFERENDUMS_ABI && \
                add_eosio_code_permission "refe.bitcash"
                ;;
            8)
                echo "Complete setup (deploy + permissions + cross-contract)..."
                deploy_contract "prop.bitcash" $PROPOSALS_WASM $PROPOSALS_ABI && \
                add_eosio_code_permission "prop.bitcash" && \
                deploy_contract "refe.bitcash" $REFERENDUMS_WASM $REFERENDUMS_ABI && \
                add_eosio_code_permission "refe.bitcash" && \
                setup_cross_contract_permission
                ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        echo ""
    done
}

# Execute the main menu
main_menu
