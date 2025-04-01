#!/usr/bin/env bash

####
# Once private network is setup and running with legacy consensus algo
# we can switch over to new finality method
# For each producers we will register new BLS keys
# and `switchtosvnn` will activate Savanna Algorithm
####

# Source configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/config.sh"

# Source secure keys if available
if [ -f "$SECURE_KEYS_FILE" ]; then
  source "$SECURE_KEYS_FILE"
fi

# unwindw our producer finalizer keys and make activating call
# New System Contracts Replace with actions regfinkey, and switchtosvnn
# regfinkey [producer name] [public key] [proof of possession]
counter=0
for producer_name in "${PRODUCERS[@]}"
do
    # Execute the cleos command error if vars not set
    # void system_contract::regfinkey( const name& finalizer_name, const std::string& finalizer_key, const std::string& proof_of_possession)
    cleos --url $ENDPOINT push action eosio regfinkey "{\"finalizer_name\":\"${producer_name:?}\", \
                            \"finalizer_key\":\"${PUBLIC_KEY[$counter]:?}\", \
                            \"proof_of_possession\":\"${PROOF_POSSESION[$counter]:?}\"}" -p ${producer_name:?}
    let counter+=1
done

sleep 1

# switchtosvnn
# void system_contract::switchtosvnn()
cleos --url $ENDPOINT push action eosio switchtosvnn '{}' -p eosio
