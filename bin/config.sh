#!/usr/bin/env bash

# Network endpoints
ENDPOINT="http://127.0.0.1:8888"
NODEOS_ONE_PORT=8888
NODEOS_TWO_PORT=6888
NODEOS_THREE_PORT=7888

# Directory paths
ROOT_DIR="/data/chain-data"
LOG_DIR="/data/chain-data/log"
WALLET_DIR="/data/chain-data/wallet"
CONTRACT_DIR="/data/non-profit-chain/contracts"

# Node directories
NODE_ONE_DIR="node-alpha"
NODE_TWO_DIR="node-beta"
NODE_THREE_DIR="node-gamma"

# Config files
GENESIS_FILE="/data/non-profit-chain/config/genesis.json"
CONFIG_FILE="/data/non-profit-chain/config/config.ini"
LOGGING_JSON="/data/non-profit-chain/config/logging.json"

# Producer names corresponging to the node directories
PRODUCERS=(alpha.bp beta.bp gamma.bp)

# P2P ports
P2P_PORT_ONE=1444
P2P_PORT_TWO=2444
P2P_PORT_THREE=3444

# User account names
VOTER_ACCOUNT="voter.impact" # account that votes with 15% of the network tokens for the bp schedule to run
SPECIAL_ACCOUNTS=("bitcash" "prop.bitcash" "refe.bitcash" "fund.impact") # accounts with large amounts of IMPACT tokens

# BLS Keys are stored in a secure location
SECURE_KEYS_FILE="$ROOT_DIR/secure/bls_keys.sh"
