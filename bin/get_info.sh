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

# Function to get comprehensive account information
function get_detailed_account_info {
    if [ -z "$1" ]; then
        echo "Usage: get_detailed_account_info <account_name>"
        read -p "Enter account name: " ACCOUNT_NAME
    else
        ACCOUNT_NAME="$1"
    fi

    echo "=== Detailed Information for Account: $ACCOUNT_NAME ==="
    
    # Basic account information
    echo -e "\n--- Basic Account Info ---"
    cleos --url $API_URL get account $ACCOUNT_NAME
    
    # Account balance
    echo -e "\n--- Token Balance ---"
    cleos --url $API_URL get currency balance eosio.token $ACCOUNT_NAME IMPACT 2>/dev/null || echo "No IMPACT balance found"
    
    # Voting information
    echo -e "\n--- Voting Info ---"
    ACCOUNT_INFO=$(cleos --url $API_URL get account $ACCOUNT_NAME --json 2>/dev/null)
    if [ $? -eq 0 ] && command -v jq &> /dev/null; then
        VOTER_INFO=$(echo $ACCOUNT_INFO | jq -r '.voter_info // empty')
        if [ -n "$VOTER_INFO" ] && [ "$VOTER_INFO" != "null" ]; then
            echo "Voting details:"
            echo $ACCOUNT_INFO | jq '.voter_info'
        else
            echo "Account has not voted yet"
        fi
    else
        echo "Could not retrieve voting information"
    fi
    
    # RAM usage
    echo -e "\n--- RAM Usage ---"
    if [ $? -eq 0 ] && command -v jq &> /dev/null; then
        RAM_QUOTA=$(echo $ACCOUNT_INFO | jq -r '.ram_quota // 0')
        RAM_USAGE=$(echo $ACCOUNT_INFO | jq -r '.ram_usage // 0')
        if [ "$RAM_QUOTA" != "0" ]; then
            RAM_PERCENT=$(echo "scale=2; ($RAM_USAGE * 100) / $RAM_QUOTA" | bc -l 2>/dev/null || echo "N/A")
            echo "RAM Quota: $RAM_QUOTA bytes"
            echo "RAM Usage: $RAM_USAGE bytes"
            echo "RAM Usage Percentage: $RAM_PERCENT%"
        else
            echo "No RAM information available"
        fi
    fi
    
    # Staked resources
    echo -e "\n--- Staked Resources ---"
    if command -v jq &> /dev/null; then
        NET_WEIGHT=$(echo $ACCOUNT_INFO | jq -r '.net_weight // "0"')
        CPU_WEIGHT=$(echo $ACCOUNT_INFO | jq -r '.cpu_weight // "0"')
        echo "NET Weight: $NET_WEIGHT"
        echo "CPU Weight: $CPU_WEIGHT"
    fi
    
    # Producer information (if account is a producer)
    echo -e "\n--- Producer Information ---"
    PRODUCER_INFO=$(cleos --url $API_URL get table eosio eosio producers --lower $ACCOUNT_NAME --upper $ACCOUNT_NAME --json 2>/dev/null)
    if [ $? -eq 0 ] && command -v jq &> /dev/null; then
        PRODUCER_DATA=$(echo $PRODUCER_INFO | jq -r '.rows[0] // empty')
        if [ -n "$PRODUCER_DATA" ] && [ "$PRODUCER_DATA" != "null" ]; then
            echo "Account is a registered producer:"
            echo $PRODUCER_INFO | jq '.rows[0]'
        else
            echo "Account is not a registered producer"
        fi
    else
        echo "Could not retrieve producer information"
    fi
    
    # Transaction history (last few actions)
    echo -e "\n--- Recent Actions ---"
    cleos --url $API_URL get actions $ACCOUNT_NAME -1 -5 2>/dev/null || echo "Could not retrieve recent actions"
}

# Function to display menu
function show_menu {
    echo "=== Blockchain Information Menu ==="
    echo "1. Get blockchain info"
    echo "2. Get account keys for configured accounts"
    echo "3. Get system accounts info"
    echo "4. Get detailed account information"
    echo "5. Run all functions"
    echo "0. Exit"
    echo "=================================="
}

# Main menu loop
function main_menu {
    while true; do
        show_menu
        read -p "Choose an option [0-5]: " choice
        
        case $choice in
            1)
                echo "Getting blockchain information..."
                get_blockchain_info
                ;;
            2)
                echo "Getting account keys..."
                get_account_keys
                ;;
            3)
                echo "Getting system accounts info..."
                get_system_accounts_info
                ;;
            4)
                echo "Getting detailed account information..."
                read -p "Enter account name: " account_name
                get_detailed_account_info "$account_name"
                ;;
            5)
                echo "Running all functions..."
                get_blockchain_info
                get_account_keys
                get_system_accounts_info
                ;;
            0)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
        clear
    done
}

# Execute the main menu (replace the previous automatic execution)
clear
main_menu
