#!/bin/bash

# Source configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/config.sh"

# Use ENDPOINT from config.sh
API_URL="$ENDPOINT"

# Function to retrieve and display blockchain information
function get_blockchain_info {
    echo "Retrieving blockchain information from $API_URL..."

    # Get current blockchain information
    echo -e "\n--- Blockchain Info ---"
    cleos --url $API_URL get info

    # Get information on the latest block - with fallback if jq not available
    if command -v jq &> /dev/null; then
        LATEST_BLOCK=$(cleos --url $API_URL get info | jq -r '.head_block_num')
    else
        LATEST_BLOCK=$(cleos --url $API_URL get info | grep -o '"head_block_num":[0-9]*' | sed 's/"head_block_num"://')
    fi

    if [ -n "$LATEST_BLOCK" ]; then
        echo -e "\n--- Latest Block ($LATEST_BLOCK) ---"
        cleos --url $API_URL get block $LATEST_BLOCK
    else
        echo -e "\n--- Could not determine latest block number ---"
    fi

    # Get account information
    ACCOUNT="eosio"
    echo -e "\n--- Account Info for '$ACCOUNT' ---"
    cleos --url $API_URL get account $ACCOUNT

    # Get producer schedule
    echo -e "\n--- Producer Schedule ---"
    cleos --url $API_URL get schedule
}

# Function to retrieve and display public keys for special accounts
function get_account_keys {
    echo -e "\n--- Account Keys ---"
    
    # Check voter account
    echo -e "\n--- Voter Account: $VOTER_ACCOUNT ---"
    ACCOUNT_INFO=$(cleos --url $API_URL get account $VOTER_ACCOUNT --json 2>/dev/null)
    if [ $? -eq 0 ]; then
        OWNER_KEYS=$(echo $ACCOUNT_INFO | jq -r '.permissions[] | select(.perm_name == "owner") | .required_auth.keys[].key')
        ACTIVE_KEYS=$(echo $ACCOUNT_INFO | jq -r '.permissions[] | select(.perm_name == "active") | .required_auth.keys[].key')

        echo "Owner Keys:"
        if [ -n "$OWNER_KEYS" ]; then
            echo "$OWNER_KEYS"
        else
            echo "No owner keys found."
        fi

        echo "Active Keys:"
        if [ -n "$ACTIVE_KEYS" ]; then
            echo "$ACTIVE_KEYS"
        else
            echo "No active keys found."
        fi
    else
        echo "Failed to retrieve information for voter account: $VOTER_ACCOUNT"
    fi
    
    # Check producer accounts
    echo -e "\n--- Producer Accounts ---"
    for ACCOUNT in "${PRODUCERS[@]}"
    do
        echo -e "\n--- Producer: $ACCOUNT ---"
        ACCOUNT_INFO=$(cleos --url $API_URL get account $ACCOUNT --json 2>/dev/null)
        if [ $? -eq 0 ]; then
            OWNER_KEYS=$(echo $ACCOUNT_INFO | jq -r '.permissions[] | select(.perm_name == "owner") | .required_auth.keys[].key')
            ACTIVE_KEYS=$(echo $ACCOUNT_INFO | jq -r '.permissions[] | select(.perm_name == "active") | .required_auth.keys[].key')

            echo "Owner Keys:"
            if [ -n "$OWNER_KEYS" ]; then
                echo "$OWNER_KEYS"
            else
                echo "No owner keys found."
            fi

            echo "Active Keys:"
            if [ -n "$ACTIVE_KEYS" ]; then
                echo "$ACTIVE_KEYS"
            else
                echo "No active keys found."
            fi
        else
            echo "Failed to retrieve information for producer account: $ACCOUNT"
        fi
    done
    
    # Check special accounts
    echo -e "\n--- Special Accounts ---"
    for ACCOUNT in "${SPECIAL_ACCOUNTS[@]}"
    do
        echo -e "\n--- Special Account: $ACCOUNT ---"
        ACCOUNT_INFO=$(cleos --url $API_URL get account $ACCOUNT --json 2>/dev/null)
        if [ $? -eq 0 ]; then
            OWNER_KEYS=$(echo $ACCOUNT_INFO | jq -r '.permissions[] | select(.perm_name == "owner") | .required_auth.keys[].key')
            ACTIVE_KEYS=$(echo $ACCOUNT_INFO | jq -r '.permissions[] | select(.perm_name == "active") | .required_auth.keys[].key')

            echo "Owner Keys:"
            if [ -n "$OWNER_KEYS" ]; then
                echo "$OWNER_KEYS"
            else
                echo "No owner keys found."
            fi

            echo "Active Keys:"
            if [ -n "$ACTIVE_KEYS" ]; then
                echo "$ACTIVE_KEYS"
            else
                echo "No active keys found."
            fi
        else
            echo "Failed to retrieve information for special account: $ACCOUNT"
        fi
    done
}

# Add this function before the "Execute the functions" line
function get_system_accounts_info {
    echo -e "\n--- System Accounts Status ---"
    
    # Define system accounts array
    SYSTEM_ACCOUNTS=(
        "eosio"
        "eosio.ram"
        "eosio.ramfee"
        "eosio.stake"
        "eosio.token"
        "eosio.rex"
        "eosio.fees"
        "eosio.msig"
    )

    # Check voter account first
    echo -e "\n=== Voter Account ($VOTER_ACCOUNT) ==="
    echo -e "\nPermissions:"
    cleos --url $API_URL get account $VOTER_ACCOUNT

    # Check each system account
    for account in "${SYSTEM_ACCOUNTS[@]}"
    do
        echo -e "\n=== System Account ($account) ==="
        echo -e "\nPermissions:"
        cleos --url $API_URL get account $account
    done
}

# Execute the functions
get_blockchain_info
get_account_keys
get_system_accounts_info
