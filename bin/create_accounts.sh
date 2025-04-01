#!/usr/bin/env bash

ENDPOINT=$1
WALLET_DIR=$2
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/config.sh"

# create producers error out if vars not set
for producer_name in "${PRODUCERS[@]}"
do
    [ ! -s "$WALLET_DIR/${producer_name}.keys" ] && cleos create key --to-console > "$WALLET_DIR/${producer_name}.keys"
    # head because we want the first match; they may be multiple keys
    PRIVATE_KEY=$(grep Private "$WALLET_DIR/${producer_name}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
    PUBLIC_KEY=$(grep Public "$WALLET_DIR/${producer_name}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
    cleos wallet import --name network-wallet --private-key $PRIVATE_KEY

    cleos --url $ENDPOINT system newaccount eosio ${producer_name:?} ${PUBLIC_KEY:?} --stake-net "500 IMPACT" --stake-cpu "500 IMPACT" --buy-ram "1000 IMPACT"
    # get some spending money
    cleos --url $ENDPOINT transfer eosio ${producer_name} "10000 IMPACT" "init funding"
    # self stake some net and cpu
    cleos --url $ENDPOINT system delegatebw ${producer_name} ${producer_name} "4000.0 IMPACT" "4000.0 IMPACT"
done

# create user keys
[ ! -s "$WALLET_DIR/user.keys" ] && cleos create key --to-console > "$WALLET_DIR/user.keys"
# head because we want the first match; they may be multiple keys
USER_PRIVATE_KEY=$(grep Private "$WALLET_DIR/user.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
USER_PUBLIC_KEY=$(grep Public "$WALLET_DIR/user.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
cleos wallet import --name network-wallet --private-key $USER_PRIVATE_KEY

# create user account with large amt of funds
for user_name in $VOTER_ACCOUNT
do
  # create user account
  cleos --url $ENDPOINT system newaccount eosio ${user_name:?} ${USER_PUBLIC_KEY:?} --stake-net "50 IMPACT" --stake-cpu "50 IMPACT" --buy-ram "100 IMPACT"
  # get some spending money
  cleos --url $ENDPOINT transfer eosio ${user_name} "150000000 IMPACT" "init funding"
  # stake 150M IMPACT
  cleos --url $ENDPOINT system delegatebw ${user_name} ${user_name} "75000000.000 IMPACT" "75000000.0000 IMPACT"
done

# create special accounts with substantial resources
for special_account in "${SPECIAL_ACCOUNTS[@]}"
do
  # Create account with substantial initial resources
  cleos --url $ENDPOINT system newaccount eosio ${special_account:?} ${USER_PUBLIC_KEY:?} --stake-net "5000 IMPACT" --stake-cpu "5000 IMPACT" --buy-ram "50000 IMPACT"
  
  # Transfer large amount of tokens but keep most unstaked
  cleos --url $ENDPOINT transfer eosio ${special_account} "1000000 IMPACT" "init funding"
  
  # Stake only a portion, leaving most liquid
  cleos --url $ENDPOINT system delegatebw ${special_account} ${special_account} "100000.000 IMPACT" "100000.0000 IMPACT"
  
  # Buy additional RAM
  cleos --url $ENDPOINT system buyram ${special_account} ${special_account} "10000 IMPACT"
done
