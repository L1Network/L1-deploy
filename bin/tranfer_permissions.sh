#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/config.sh"

# Transfer control of all system accounts including eosio to voter account
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

for account in "${SYSTEM_ACCOUNTS[@]}"
do
    cleos --url $ENDPOINT set account permission $account active "{\"threshold\":1,\"keys\":[],\"accounts\":[{\"permission\":{\"actor\":\"$VOTER_ACCOUNT\",\"permission\":\"active\"},\"weight\":1}]}" owner -p $account@owner
    cleos --url $ENDPOINT set account permission $account owner "{\"threshold\":1,\"keys\":[],\"accounts\":[{\"permission\":{\"actor\":\"$VOTER_ACCOUNT\",\"permission\":\"active\"},\"weight\":1}]}" -p $account@owner
done 