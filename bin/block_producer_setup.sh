#!/usr/bin/env bash

ENDPOINT_ONE=$1
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

    # register producer
    cleos --url $ENDPOINT_ONE system regproducer ${producer_name} ${PUBLIC_KEY}
done

# create user keys
[ ! -s "$WALLET_DIR/user.keys" ] && cleos create key --to-console > "$WALLET_DIR/user.keys"
# head because we want the first match; they may be multiple keys
USER_PRIVATE_KEY=$(grep Private "$WALLET_DIR/user.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
cleos wallet import --name network-wallet --private-key $USER_PRIVATE_KEY

# now have all users vote for all producers
for user_name in $VOTER_ACCOUNT
do
  # vote
  cleos --url $ENDPOINT_ONE system voteproducer prods ${user_name} "${PRODUCERS[@]}"
done