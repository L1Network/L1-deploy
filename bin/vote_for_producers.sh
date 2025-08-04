#!/usr/bin/env bash

# Script to vote for specific block producers from a chosen account
# Usage: ./vote_for_producers.sh <endpoint> <voter_account> <producer1> <producer2> ... <producerN>

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <endpoint> <voter_account> <producer1> <producer2> ... <producerN>"
    echo "Example: $0 http://127.0.0.1:8888 myaccount producer1 producer2 producer3"
    exit 1
fi

ENDPOINT=$1
VOTER_ACCOUNT=$2
shift 2  # Remove endpoint and voter_account from arguments
PRODUCERS=("$@")  # Remaining arguments are producers

echo "Voting for producers: ${PRODUCERS[*]}"
echo "From account: $VOTER_ACCOUNT"

# Vote for the specified producers
cleos --url $ENDPOINT system voteproducer prods $VOTER_ACCOUNT "${PRODUCERS[@]}"

# Verify the vote
echo "Verifying vote..."
cleos --url $ENDPOINT get account $VOTER_ACCOUNT 