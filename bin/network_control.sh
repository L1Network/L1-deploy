#!/usr/bin/env bash

####
# Once antelope software is build and installed
# script to manage private network
# CREATE new network with 3 nodes
# CLEAN out data from previous network
# STOP all nodes on network
# START 3 node network
####

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Source configuration
source "${SCRIPT_DIR}/config.sh"

COMMAND=${1:-"NA"}

######
# Stop Function to shutdown all nodes
#####
stop_func() {
  MY_ID=$(id -u)
  for p in $(ps -u $MY_ID | grep nodeos | sed -e 's/^[[:space:]]*//' | cut -d" " -f1); do
    echo $p && kill -15 $p
  done
  echo "waiting for production network to quiesce..."
  sleep 5
}
### END STOP Command

#####
# Check Percent Used Space
#####
check_used_space() {
  # check used space ; threshhold is 90%
  threshold=90
  percent_used=$(df -h "${ROOT_DIR:?}" | awk 'NR==2 {print $5}' | sed 's/%//')
  if [ ${percent_used:-100} -gt ${threshold} ]; then
    echo "ERROR: ${ROOT_DIR} is full at ${percent_used:-100}%. Must be less then ${threshold}%."
    return 127
  else
    return 0
  fi
}

#####
# START/CREATE Function to startup all nodes
####
start_func() {
  COMMAND=$1

  check_used_space
  USED_SPACE=$?

  if [ $USED_SPACE -ne 0 ]; then
    echo "Exiting not enough free space"
    exit 127
  fi

  # create private key
  [ ! -d "$WALLET_DIR" ] && mkdir -p "$WALLET_DIR"
  [ ! -s "$WALLET_DIR"/network.keys ] && cleos create key --to-console > "$WALLET_DIR"/network.keys
  # head because we want the first match; they may be multiple keys
  EOS_ROOT_PRIVATE_KEY=$(grep Private "${WALLET_DIR}"/network.keys | head -1 | cut -d: -f2 | sed 's/ //g')
  EOS_ROOT_PUBLIC_KEY=$(grep Public "${WALLET_DIR}"/network.keys | head -1 | cut -d: -f2 | sed 's/ //g')
  # create keys for first three producers
  for producer_name in "${PRODUCERS[@]}"
  do
      [ ! -s "$WALLET_DIR/${producer_name}.keys" ] && cleos create key --to-console > "$WALLET_DIR/${producer_name}.keys"
  done

  # create initialize genesis file; create directories; copy cofigs into place
  if [ "$COMMAND" == "CREATE" ]; then
    NOW=$(date +%FT%T.%3N)
    sed "s/\"initial_key\": \".*\",/\"initial_key\": \"${EOS_ROOT_PUBLIC_KEY}\",/" $GENESIS_FILE > /tmp/genesis.json
    sed "s/\"initial_timestamp\": \".*\",/\"initial_timestamp\": \"${NOW}\",/" /tmp/genesis.json > ${ROOT_DIR}/genesis.json
    [ ! -d "$LOG_DIR" ] && mkdir -p "$LOG_DIR"
    [ ! -d "$ROOT_DIR"/"$NODE_ONE_DIR"/data ] && mkdir -p "$ROOT_DIR"/"$NODE_ONE_DIR"/data
    [ ! -d "$ROOT_DIR"/"$NODE_TWO_DIR"/data ] && mkdir -p "$ROOT_DIR"/"$NODE_TWO_DIR"/data
    [ ! -d "$ROOT_DIR"/"$NODE_THREE_DIR"/data ] && mkdir -p "$ROOT_DIR"/"$NODE_THREE_DIR"/data
    # setup common config, shared by all nodoes instances
    cp "${CONFIG_FILE}" ${ROOT_DIR}/config.ini
    cp "${LOGGING_JSON}" ${ROOT_DIR}/logging.json
  fi

  # setup wallet
  "$SCRIPT_DIR"/open_wallet.sh "$WALLET_DIR"
  # Import Root Private Key
  cleos wallet import --name network-wallet --private-key $EOS_ROOT_PRIVATE_KEY

  # start nodeos one always allow stale production
  if [ "$COMMAND" == "CREATE" ]; then
    nodeos --genesis-json ${ROOT_DIR}/genesis.json --agent-name "Node One" \
      --http-server-address 0.0.0.0:${NODEOS_ONE_PORT} \
      --p2p-listen-endpoint 0.0.0.0:${P2P_PORT_ONE} \
      --enable-stale-production \
      --producer-name eosio \
      --signature-provider ${EOS_ROOT_PUBLIC_KEY}=KEY:${EOS_ROOT_PRIVATE_KEY} \
      --config "$ROOT_DIR"/config.ini \
      --data-dir "$ROOT_DIR"/"$NODE_ONE_DIR"/data > $LOG_DIR/$NODE_ONE_DIR.log 2>&1 &
    NODEOS_ONE_PID=$!

    # create accounts, activate protocols, create tokens, set system contracts
    sleep 1
    "$SCRIPT_DIR"/boot_actions.sh "$ENDPOINT" "$CONTRACT_DIR" "$EOS_ROOT_PUBLIC_KEY"
    sleep 1
    # create producer and user accounts, stake IMPACT
    "$SCRIPT_DIR"/create_accounts.sh "$ENDPOINT" "$WALLET_DIR"
    sleep 1
    # register producers and users vote for producers
    "$SCRIPT_DIR"/block_producer_setup.sh "$ENDPOINT" "$WALLET_DIR"
    # need a long sleep here to allow time for new production schedule to settle
    echo "please wait 5 seconds while we wait for new producer schedule to settle"
    sleep 5
    kill -15 $NODEOS_ONE_PID
    # wait for shutdown
    sleep 5
  fi

  # if CREATE we bootstraped the node and killed it
  # if START we have no node running
  # either way we need to start Node One
  PRODUCER_ONE_PRIVATE_KEY=$(grep Private "$WALLET_DIR/${PRODUCERS[0]}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
  PRODUCER_ONE_PUBLIC_KEY=$(grep Public "$WALLET_DIR/${PRODUCERS[0]}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
  nodeos --agent-name "Node One" \
    --http-server-address 0.0.0.0:${NODEOS_ONE_PORT} \
    --p2p-listen-endpoint 0.0.0.0:${P2P_PORT_ONE} \
    --enable-stale-production \
    --producer-name ${PRODUCERS[0]} \
    --signature-provider ${PRODUCER_ONE_PUBLIC_KEY}=KEY:${PRODUCER_ONE_PRIVATE_KEY} \
    --config "$ROOT_DIR"/config.ini \
    --data-dir "$ROOT_DIR"/"$NODE_ONE_DIR"/data \
    --p2p-peer-address 127.0.0.1:${P2P_PORT_TWO} \
    --p2p-peer-address 127.0.0.1:${P2P_PORT_THREE} --logconf "$ROOT_DIR"/logging.json > $LOG_DIR/$NODE_ONE_DIR.log 2>&1 &

  # start nodeos two
  echo "please wait while we fire up the second node"
  sleep 2

  PRODUCER_TWO_PRIVATE_KEY=$(grep Private "$WALLET_DIR/${PRODUCERS[1]}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
  PRODUCER_TWO_PUBLIC_KEY=$(grep Public "$WALLET_DIR/${PRODUCERS[1]}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
  if [ "$COMMAND" == "CREATE" ]; then
    nodeos --genesis-json ${ROOT_DIR}/genesis.json --agent-name "Node Two" \
      --http-server-address 0.0.0.0:${NODEOS_TWO_PORT} \
      --p2p-listen-endpoint 0.0.0.0:${P2P_PORT_TWO} \
      --enable-stale-production \
      --producer-name ${PRODUCERS[1]} \
      --signature-provider ${PRODUCER_TWO_PUBLIC_KEY}=KEY:${PRODUCER_TWO_PRIVATE_KEY} \
      --config "$ROOT_DIR"/config.ini \
      --data-dir "$ROOT_DIR"/"$NODE_TWO_DIR"/data \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_ONE} \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_THREE} > $LOG_DIR/$NODE_TWO_DIR.log 2>&1 &
  else
    nodeos --agent-name "Node Two" \
      --http-server-address 0.0.0.0:${NODEOS_TWO_PORT} \
      --p2p-listen-endpoint 0.0.0.0:${P2P_PORT_TWO} \
      --enable-stale-production \
      --producer-name ${PRODUCERS[1]} \
      --signature-provider ${PRODUCER_TWO_PUBLIC_KEY}=KEY:${PRODUCER_TWO_PRIVATE_KEY} \
      --config "$ROOT_DIR"/config.ini \
      --data-dir "$ROOT_DIR"/"$NODE_TWO_DIR"/data \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_ONE} \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_THREE} > $LOG_DIR/$NODE_TWO_DIR.log 2>&1 &
  fi
  echo "please wait while we fire up the third node"
  sleep 5

  PRODUCER_THREE_PRIVATE_KEY=$(grep Private "$WALLET_DIR/${PRODUCERS[2]}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
  PRODUCER_THREE_PUBLIC_KEY=$(grep Public "$WALLET_DIR/${PRODUCERS[2]}.keys" | head -1 | cut -d: -f2 | sed 's/ //g')
  if [ "$COMMAND" == "CREATE" ]; then
    nodeos --genesis-json ${ROOT_DIR}/genesis.json --agent-name "Node Three" \
      --http-server-address 0.0.0.0:${NODEOS_THREE_PORT} \
      --p2p-listen-endpoint 0.0.0.0:${P2P_PORT_THREE} \
      --enable-stale-production \
      --producer-name ${PRODUCERS[2]} \
      --signature-provider ${PRODUCER_THREE_PUBLIC_KEY}=KEY:${PRODUCER_THREE_PRIVATE_KEY} \
      --config "$ROOT_DIR"/config.ini \
      --data-dir "$ROOT_DIR"/"$NODE_THREE_DIR"/data \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_ONE} \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_TWO} > $LOG_DIR/$NODE_THREE_DIR.log 2>&1 &
  else
    nodeos --agent-name "Node Three" \
      --http-server-address 0.0.0.0:${NODEOS_THREE_PORT} \
      --p2p-listen-endpoint 0.0.0.0:${P2P_PORT_THREE} \
      --enable-stale-production \
      --producer-name ${PRODUCERS[2]} \
      --signature-provider ${PRODUCER_THREE_PUBLIC_KEY}=KEY:${PRODUCER_THREE_PRIVATE_KEY} \
      --config "$ROOT_DIR"/config.ini \
      --data-dir "$ROOT_DIR"/"$NODE_THREE_DIR"/data \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_ONE} \
      --p2p-peer-address 127.0.0.1:${P2P_PORT_TWO} > $LOG_DIR/$NODE_THREE_DIR.log 2>&1 &
  fi

  echo "waiting for production network to sync up..."
  sleep 20
}
## end START/CREATE COMMAND

echo "STARTING COMMAND ${COMMAND}"

if [ "$COMMAND" == "NA" ]; then
  echo "usage: network_control.sh [CREATE|START|CLEAN|STOP|SAVANNA]"
  exit 1
fi

if [ "$COMMAND" == "CLEAN" ]; then
    # Stop any running nodes first
    stop_func
    # Remove everything in ROOT_DIR
    rm -rf "$ROOT_DIR"/*
    # Recreate basic directory structure
    mkdir -p "$ROOT_DIR"/"$NODE_ONE_DIR"/data
    mkdir -p "$ROOT_DIR"/"$NODE_TWO_DIR"/data
    mkdir -p "$ROOT_DIR"/"$NODE_THREE_DIR"/data
    mkdir -p "$LOG_DIR"
fi

if [ "$COMMAND" == "CREATE" ] || [ "$COMMAND" == "START" ]; then
  start_func $COMMAND
  
  # If it's CREATE command, automatically activate SAVANNA after a delay
  if [ "$COMMAND" == "CREATE" ]; then
    echo "Waiting 30 seconds before activating SAVANNA..."
    sleep 30
    
    echo "Automatically activating SAVANNA after chain creation..."
    # Call SAVANNA functionality
    echo "creating new finalizer BLS keys"
    PUBLIC_KEY=()
    PROOF_POSSESION=()
    PRIVATE_KEY=()
    # producers
    for producer_name in "${PRODUCERS[@]}"
    do
      spring-util bls create key --to-console > "${WALLET_DIR:?}"/"${producer_name}.finalizer.key"
      PUBLIC_KEY+=( $(grep Public "${WALLET_DIR}"/"${producer_name}.finalizer.key" | cut -d: -f2 | sed 's/ //g') ) \
        || exit 127
      PRIVATE_KEY+=( $(grep Private "${WALLET_DIR}"/"${producer_name}.finalizer.key" | cut -d: -f2 | sed 's/ //g') ) \
        || exit 127
      PROOF_POSSESION+=( $(grep Possession "${WALLET_DIR}"/"${producer_name}.finalizer.key" | cut -d: -f2 | sed 's/ //g') ) \
        || exit 127
      echo "# producer ${producer_name} finalizer key" >> "$ROOT_DIR"/config.ini
      echo "signature-provider = ""${PUBLIC_KEY[@]: -1}""=KEY:""${PRIVATE_KEY[@]: -1}" >> "${ROOT_DIR}/config.ini"
    done
      
    # Store sensitive BLS keys in chain-data directory
    mkdir -p "$ROOT_DIR"/secure
    chmod 700 "$ROOT_DIR"/secure
    
    # Create secure keys file
    echo "#!/usr/bin/env bash" > "$ROOT_DIR"/secure/bls_keys.sh
    echo "" >> "$ROOT_DIR"/secure/bls_keys.sh
    echo "# BLS Keys - SENSITIVE INFORMATION" >> "$ROOT_DIR"/secure/bls_keys.sh
    echo "PUBLIC_KEY=(" >> "$ROOT_DIR"/secure/bls_keys.sh
    for key in "${PUBLIC_KEY[@]}"; do
      echo "  \"$key\"" >> "$ROOT_DIR"/secure/bls_keys.sh
    done
    echo ")" >> "$ROOT_DIR"/secure/bls_keys.sh
    echo "" >> "$ROOT_DIR"/secure/bls_keys.sh
    echo "PRIVATE_KEY=(" >> "$ROOT_DIR"/secure/bls_keys.sh
    for key in "${PRIVATE_KEY[@]}"; do
      echo "  \"$key\"" >> "$ROOT_DIR"/secure/bls_keys.sh
    done
    echo ")" >> "$ROOT_DIR"/secure/bls_keys.sh
    echo "" >> "$ROOT_DIR"/secure/bls_keys.sh
    echo "PROOF_POSSESION=(" >> "$ROOT_DIR"/secure/bls_keys.sh
    for proof in "${PROOF_POSSESION[@]}"; do
      echo "  \"$proof\"" >> "$ROOT_DIR"/secure/bls_keys.sh
    done
    echo ")" >> "$ROOT_DIR"/secure/bls_keys.sh
    chmod 600 "$ROOT_DIR"/secure/bls_keys.sh
    
    # Update config.sh to remove sensitive keys and reference the secure file
    sed -i -e "/^PUBLIC_KEY=(/,/^)/d" "$SCRIPT_DIR"/config.sh
    sed -i -e "/^PRIVATE_KEY=(/,/^)/d" "$SCRIPT_DIR"/config.sh
    sed -i -e "/^PROOF_POSSESION=(/,/^)/d" "$SCRIPT_DIR"/config.sh
    
    # Check if SECURE_KEYS_FILE entry already exists in config.sh
    if ! grep -q "SECURE_KEYS_FILE=" "$SCRIPT_DIR"/config.sh; then
      # Add reference to secure file in config.sh only if it doesn't exist
      echo "" >> "$SCRIPT_DIR"/config.sh
      echo "# BLS Keys are stored in a secure location" >> "$SCRIPT_DIR"/config.sh
      echo "SECURE_KEYS_FILE=\"$ROOT_DIR/secure/bls_keys.sh\"" >> "$SCRIPT_DIR"/config.sh
    fi

    echo "need to reload config: please wait shutting down node"
    stop_func
    # Source updated config and secure keys
    source "${SCRIPT_DIR}/config.sh"
    if [ -f "$SECURE_KEYS_FILE" ]; then
      source "$SECURE_KEYS_FILE"
    fi
    echo "need to reload config: please wait while we startup up nodes"
    start_func "START"

    echo "running final command to activate finality"
    # open wallet
    "$SCRIPT_DIR"/open_wallet.sh "$WALLET_DIR"
    # call activate_savanna.sh which now uses config.sh
    "$SCRIPT_DIR"/activate_savanna.sh
    echo "please wait for transition to Savanna consensus"
    sleep 30
    grep 'Transitioning to savanna' "$LOG_DIR"/"$NODE_ONE_DIR".log
    grep 'Transition to instant finality' "$LOG_DIR"/"$NODE_ONE_DIR".log
    
    # Transfer system accounts permissions to voter account after Savanna activation
    echo "Transferring system accounts permissions to voter account..."
    sleep 10
    "${SCRIPT_DIR}"/tranfer_permissions.sh
  fi
fi

if [ "$COMMAND" == "STOP" ]; then
  stop_func
fi

echo "COMPLETED COMMAND ${COMMAND}"
