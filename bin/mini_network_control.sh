# manage lightweight BP + API node
#
#  ▸ bp-lite    : light producer with limited history
#  ▸ api-node   : API + state history for dApps (unlimited history)
#
# Requires:
#   • Antelope nodeos 
#   • yq (YAML parser)
#   • Config directory: configs/mini/
#   • Connects to an existing blockchain network
#
# Usage:
#   ./mini_network_control.sh start    # launch both nodes
#   ./mini_network_control.sh stop     # graceful shutdown
#   ./mini_network_control.sh status   # show whether they're up
#   ./mini_network_control.sh restart  # stop → start
#   ./mini_network_control.sh create   # setup configs (one-time)
#
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "${SCRIPT_DIR}/config.sh"

# Load YAML config
CONFIG_FILE="${SCRIPT_DIR}/../config/mini_network.yaml"

# ----- make sure yq is present before first use ---------------------------
if ! command -v yq &>/dev/null; then
  echo "ERROR: 'yq' is required. Install with 'brew install yq' or 'apt-get install yq'."
  exit 1
fi

# Load and validate Main Net API endpoint
MAIN_NET_API=$(yq -r '.main_network.api_endpoint' "$CONFIG_FILE")
if [[ "$MAIN_NET_API" == "null" || -z "$MAIN_NET_API" ]]; then
  echo "ERROR: main_network.api_endpoint is a required field in config/mini_network.yaml"
  echo "       Please add it, for example: api_endpoint: \"http://127.0.0.1:8888\""
  exit 1
fi

# Load variables from YAML
MINI_BP_HTTP_PORT=$(yq -r '.network.bp_lite.http_port' "$CONFIG_FILE")
MINI_API_HTTP_PORT=$(yq -r '.network.api_node.http_port' "$CONFIG_FILE")
MINI_BP_P2P_PORT=$(yq -r '.network.bp_lite.p2p_port' "$CONFIG_FILE")
MINI_API_P2P_PORT=$(yq -r '.network.api_node.p2p_port' "$CONFIG_FILE")
MINI_STATE_HISTORY_PORT=$(yq -r '.network.api_node.state_history_port' "$CONFIG_FILE")
MINI_ROOT=$(yq -r '.paths.root' "$CONFIG_FILE")
MINI_CONFIG_ROOT=$(yq -r '.paths.config_root' "$CONFIG_FILE")
[[ "$MINI_CONFIG_ROOT" == "null" || -z "$MINI_CONFIG_ROOT" ]] && \
  MINI_CONFIG_ROOT="$(dirname "${BASH_SOURCE[0]}")/../configs/mini"
MINI_BP_NAME=$(yq -r '.node.bp_name' "$CONFIG_FILE")
MINI_PRODUCER_NAME=$(yq -r '.node.producer_name' "$CONFIG_FILE")
EXISTING_BP_ACCOUNT=$(yq -r '.existing_bp.account' "$CONFIG_FILE")
EXISTING_BP_PRIVATE_KEY=$(yq -r '.existing_bp.private_key' "$CONFIG_FILE")
EXISTING_BP_PUBLIC_KEY=$(yq -r '.existing_bp.public_key' "$CONFIG_FILE")
MINI_BP_URL=$(yq -r '.producer.url' "$CONFIG_FILE")
MINI_BP_LOCATION_CODE=$(yq -r '.producer.location_code' "$CONFIG_FILE")
MINI_STAKE_NET=$(yq -r '.producer.stake.net' "$CONFIG_FILE")
MINI_STAKE_CPU=$(yq -r '.producer.stake.cpu' "$CONFIG_FILE")
MINI_BUY_RAM=$(yq -r '.producer.buy_ram' "$CONFIG_FILE")
MINI_INITIAL_FUNDING=$(yq -r '.producer.initial_funding' "$CONFIG_FILE")
MINI_SELF_STAKE_NET=$(yq -r '.producer.self_stake.net' "$CONFIG_FILE")
MINI_SELF_STAKE_CPU=$(yq -r '.producer.self_stake.cpu' "$CONFIG_FILE")

# Load node-specific resource settings
MINI_BP_CHAIN_STATE_DB_SIZE=$(yq -r '.resources.bp_lite.chain_state_db_size' "$CONFIG_FILE")
MINI_BP_BLOCK_HISTORY_LIMIT=$(yq -r '.resources.bp_lite.block_history_limit' "$CONFIG_FILE")
MINI_API_CHAIN_STATE_DB_SIZE=$(yq -r '.resources.api_node.chain_state_db_size' "$CONFIG_FILE")
MINI_API_BLOCK_HISTORY_LIMIT=$(yq -r '.resources.api_node.block_history_limit' "$CONFIG_FILE")

# Performance and security settings
MINI_CHAIN_THREADS=$(yq -r '.performance.chain_threads' "$CONFIG_FILE")
MINI_HTTP_THREADS=$(yq -r '.performance.http_threads' "$CONFIG_FILE")
MINI_NET_THREADS=$(yq -r '.performance.net_threads' "$CONFIG_FILE")
MINI_ALLOWED_CONNECTIONS=$(yq -r '.security.allowed_connections' "$CONFIG_FILE")
MINI_MAX_NODES_PER_HOST=$(yq -r '.security.max_nodes_per_host' "$CONFIG_FILE")
MINI_LOG_LEVEL=$(yq -r '.logging.level' "$CONFIG_FILE")

# Load P2P peers as full addresses
mapfile -t MAIN_NETWORK_P2P_PEERS < <(yq -r '.main_network.p2p_peers[]' "$CONFIG_FILE" | tr -d '\r')
mapfile -t ADDITIONAL_P2P_PEERS < <(yq -r '.additional_p2p_peers[]?' "$CONFIG_FILE" | tr -d '\r')

# Load main net API and set a default if not provided
MAIN_NET_API=$(yq -r '.main_network.api_endpoint' "$CONFIG_FILE")
[[ "$MAIN_NET_API" == "null" || -z "$MAIN_NET_API" ]] && {
  first_peer=$(yq -r '.main_network.p2p_peers[0]' "$CONFIG_FILE")
  MAIN_NET_API="http://${first_peer%:*}:8888" # Assumes default http port 8888
}

# Validate main network peers
if [[ ${#MAIN_NETWORK_P2P_PEERS[@]} -eq 0 ]]; then
  echo "ERROR: main_network.p2p_peers must be specified in mini_network.yaml"
  echo "Example: ['127.0.0.1:9876', '127.0.0.1:9877']"
  exit 1
fi

NODEOS_BIN="$(command -v nodeos || true)"
: "${NODEOS_BIN:?nodeos not found in \$PATH}"
command -v cleos >/dev/null || { echo "ERROR: cleos not found in \$PATH"; exit 1; }

declare -Ar NODES=(
  [bp-lite]="bp-lite|${MINI_CONFIG_ROOT}/bp-lite|${MINI_ROOT}/bp-lite|${MINI_BP_P2P_PORT}|${MINI_BP_HTTP_PORT}"
  [api-node]="api-node|${MINI_CONFIG_ROOT}/api-node|${MINI_ROOT}/api-node|${MINI_API_P2P_PORT}|${MINI_API_HTTP_PORT}"
)
#          name        cfg_dir                      data_dir                p2p                   http

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pidfile() { echo "$1/nodeos.pid"; }

running() {
  local pid_file
  pid_file="$(pidfile "$1")"
  # Check if pid file exists and if a process with that PID is running
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(<"$pid_file")
    if [[ -d "/proc/$pid" ]] || ps -p "$pid" > /dev/null; then
      return 0
    fi
  fi
  return 1
}

rotate_logs_if_needed() {
  local data_dir="$1"
  local name="$2"
  local log_file="$data_dir/logs/nodeos.log"
  
  if [[ -f "$log_file" ]]; then
    local log_size_mb=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    log_size_mb=$((log_size_mb / 1024 / 1024))
    
    if [[ $log_size_mb -gt 100 ]]; then
      echo "[$name] log file is ${log_size_mb}MB, truncating to keep under 100MB"
      
      # Simply truncate the log file
      > "$log_file"
      
      echo "[$name] log truncated, starting fresh"
    fi
  fi
}

start_node() {
  local spec="$1"; IFS='|' read -r name cfg data p2p http <<<"$spec"

  if running "$data"; then
    echo "[$name] already running (PID $(<"$(pidfile "$data")"))"
    return
  fi

  mkdir -p "$data/logs" "$data/data"
  
  # Check and rotate logs if needed before starting
  rotate_logs_if_needed "$data" "$name"
  
  echo "[$name] starting on :$http (p2p :$p2p)..."

  # Load keys for this node
  local keys_file="$cfg/keys.txt"
  if [[ ! -f "$keys_file" ]]; then
    echo "[$name] ERROR: keys file not found: $keys_file"
    return 1
  fi

  local public_key private_key
  public_key=$(grep "Public key:" "$keys_file" | cut -d: -f2 | tr -d ' ')
  private_key=$(grep "Private key:" "$keys_file" | cut -d: -f2 | tr -d ' ')

  # *** CRITICAL FIX HERE ***
  # Build signature provider arguments
  local sig_args=(--signature-provider "${public_key}=KEY:${private_key}")
  
  # Add BLS signature provider for BP node
  if [[ "$name" == "bp-lite" ]]; then
    local bls_keys_file="$cfg/bls_finalizer.key"
    if [[ -f "$bls_keys_file" && -s "$bls_keys_file" ]]; then
      local bls_public_key bls_private_key
      bls_public_key=$(grep "Public key:" "$bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
      bls_private_key=$(grep "Private key:" "$bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
      
      if [[ -n "$bls_public_key" && -n "$bls_private_key" ]]; then
        # Append BLS key to the arguments array
        sig_args+=(--signature-provider "${bls_public_key}=KEY:${bls_private_key}")
        echo "[$name] using BLS finalizer keys for Savanna consensus"
      fi
    else
      echo "[$name] WARNING: No BLS keys found - node may not participate in finality"
    fi
  fi

  # Only use genesis file if this is a fresh start (no blockchain data)
  local genesis_args=()
  if [[ ! -f "$data/data/blocks/blocks.log" ]]; then
    echo "[$name] fresh start - using IMPACT genesis file"
    genesis_args+=(--genesis-json "$GENESIS_FILE_ACTIVE")
  else
    echo "[$name] continuing from existing blockchain data"
  fi

  (
    exec "$NODEOS_BIN" \
      --data-dir "$data/data" \
      --config-dir "$cfg" \
      "${genesis_args[@]}" \
      --p2p-listen-endpoint "0.0.0.0:$p2p" \
      --http-server-address "0.0.0.0:$http" \
      "${sig_args[@]}" \
      >>"$data/logs/nodeos.log" 2>&1
  ) &
  echo $! >"$(pidfile "$data")"
  
  sleep 2
  if running "$data"; then
    echo "[$name] started successfully"
  else
    echo "[$name] failed to start - check $data/logs/nodeos.log"
  fi
}

stop_node() {
  local spec="$1"; IFS='|' read -r name _ data _ _ <<<"$spec"

  if ! running "$data"; then
    echo "[$name] not running"
    rm -f "$(pidfile "$data")"
    return
  fi

  local pid; pid=$(<"$(pidfile "$data")")
  echo "[$name] stopping (PID $pid)..."
  kill -SIGINT "$pid"

  # Wait up to 30s for clean shutdown
  for _ in {1..30}; do
    sleep 1
    if ! running "$data"; then
      break
    fi
  done

  if running "$data"; then
    echo "[$name] forcing shutdown"
    kill -SIGKILL "$pid"
  fi
  rm -f "$(pidfile "$data")"
  echo "[$name] stopped"
}

print_status() {
  local spec="$1"; IFS='|' read -r name _ data _ http <<<"$spec"
  if running "$data"; then
    echo -e "[$name] \e[32mRUNNING\e[0m on :$http (PID $(<"$(pidfile "$data")"))"
    
    # Check block count for bp-lite
    if [[ "$name" == "bp-lite" ]] && command -v cleos >/dev/null; then
      local blocks
      blocks=$(cleos -u "http://127.0.0.1:$http" get info 2>/dev/null | grep head_block_num | cut -d: -f2 | tr -d ' ,' || echo "0")
      local block_limit
      block_limit=$(yq -r '.resources.bp_lite.block_history_limit' "$CONFIG_FILE")
      if [[ $blocks -ge $block_limit ]]; then
        echo -e "    \e[33mWARNING\e[0m: Block limit reached ($blocks/${block_limit})"
      else
        echo "    Blocks: $blocks/${block_limit}"
      fi
    fi
  else
    echo -e "[$name] \e[31mSTOPPED\e[0m"
  fi
}

register_producer() {
  local main_endpoint="$MAIN_NET_API"
  local bp_keys_file="${MINI_CONFIG_ROOT}/bp-lite/keys.txt"
  
  echo "🔑 Registering mini BP on main network via ${main_endpoint}..."
  
  if [[ -n "$EXISTING_BP_ACCOUNT" ]]; then
    echo "✅ Using existing BP account: $EXISTING_BP_ACCOUNT"
    echo "   Skipping account creation and registration."
    echo "   Only checking BLS finalizer registration..."
    check_finalizer_registration
    return $?
  fi
  
  if [[ ! -f "$bp_keys_file" ]]; then
    echo "❌ BP keys not found. Run 'create' command first."
    return 1
  fi
  
  local public_key private_key
  public_key=$(grep "Public key:" "$bp_keys_file" | cut -d: -f2 | tr -d ' ')
  private_key=$(grep "Private key:" "$bp_keys_file" | cut -d: -f2 | tr -d ' ')
  
  if [[ -z "$public_key" || -z "$private_key" ]]; then
    echo "❌ Could not extract keys from $bp_keys_file"
    return 1
  fi
  
  echo "Setting up wallet..."
  "$SCRIPT_DIR"/open_wallet.sh "$WALLET_DIR" || {
    echo "❌ Failed to open wallet"
    return 1
  }
  
  cleos wallet import --name network-wallet --private-key "$private_key" 2>/dev/null || true
  
  if ! cleos -u "$main_endpoint" get info >/dev/null 2>&1; then
    echo "❌ Cannot connect to main network at $main_endpoint"
    echo "   Make sure main network is running and api_endpoint in YAML is correct."
    return 1
  fi
  
  if cleos -u "$main_endpoint" get account "$MINI_PRODUCER_NAME" >/dev/null 2>&1; then
    echo "✅ Account $MINI_PRODUCER_NAME already exists"
  else
    echo "Creating account $MINI_PRODUCER_NAME..."
    if ! cleos -u "$main_endpoint" system newaccount eosio "$MINI_PRODUCER_NAME" "$public_key" \
      --stake-net "$MINI_STAKE_NET" --stake-cpu "$MINI_STAKE_CPU" --buy-ram "$MINI_BUY_RAM" 2>/dev/null; then
      echo "❌ Failed to create account. Make sure eosio account is available and funded."
      return 1
    fi
    
    echo "Funding account..."
    cleos -u "$main_endpoint" transfer eosio "$MINI_PRODUCER_NAME" "$MINI_INITIAL_FUNDING" "mini bp init funding" 2>/dev/null || true
    
    cleos -u "$main_endpoint" system delegatebw "$MINI_PRODUCER_NAME" "$MINI_PRODUCER_NAME" \
      "$MINI_SELF_STAKE_NET" "$MINI_SELF_STAKE_CPU" 2>/dev/null || true
  fi
  
  echo "Registering producer..."
  if cleos -u "$main_endpoint" system regproducer "$MINI_PRODUCER_NAME" "$public_key" "$MINI_BP_URL" "$MINI_BP_LOCATION_CODE" 2>/dev/null; then
    echo "✅ Producer $MINI_PRODUCER_NAME registered successfully"
  else
    echo "⚠️  Producer registration failed (may already be registered)"
  fi
  
  if [[ -n "${VOTER_ACCOUNT:-}" ]] && cleos -u "$main_endpoint" get account "$VOTER_ACCOUNT" >/dev/null 2>&1; then
    echo "Voting for mini producer..."
    
    current_vote_info=$(cleos -u "$main_endpoint" get table eosio eosio voters -l 1000 2>/dev/null | jq -r ".rows[] | select(.owner==\"$VOTER_ACCOUNT\") | .producers[]" 2>/dev/null || echo "")
    
    if echo "$current_vote_info" | grep -q "^$MINI_PRODUCER_NAME$"; then
      echo "✅ Already voting for $MINI_PRODUCER_NAME"
    else
      current_producers=$(echo "$current_vote_info" | tr '\n' ' ')
      all_producers="$current_producers $MINI_PRODUCER_NAME"
      
      if cleos -u "$main_endpoint" system voteproducer prods "$VOTER_ACCOUNT" $all_producers 2>/dev/null; then
        echo "✅ Added vote for mini producer"
      else
        echo "⚠️  Voting failed - may need manual voting"
      fi
    fi
  else
    echo "ℹ️  No voter account found - mini producer needs votes to become active"
  fi
  
  echo "✅ Mini BP registration complete!"
  
  check_finalizer_registration
  
  return 0
}

check_finalizer_registration() {
  local main_endpoint="$MAIN_NET_API"
  local bp_bls_keys_file="${MINI_CONFIG_ROOT}/bp-lite/bls_finalizer.key"
  
  echo "🔐 Checking BLS finalizer registration..."
  
  if [[ ! -f "$bp_bls_keys_file" || ! -s "$bp_bls_keys_file" ]]; then
    echo "⚠️  No BLS finalizer keys found. Run 'create' to generate them."
    return 1
  fi
  
  local bls_public_key bls_private_key proof_of_possession
  bls_public_key=$(grep "Public key:" "$bp_bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
  bls_private_key=$(grep "Private key:" "$bp_bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
  proof_of_possession=$(grep "Proof of possession:" "$bp_bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
  
  if [[ -z "$bls_public_key" || -z "$bls_private_key" ]]; then
    echo "❌ Invalid BLS keys format"
    return 1
  fi
  
  "$SCRIPT_DIR"/open_wallet.sh "$WALLET_DIR" || {
    echo "❌ Failed to open wallet"
    return 1
  }
  
  local bp_keys_file="${MINI_CONFIG_ROOT}/bp-lite/keys.txt"
  local bp_private_key
  bp_private_key=$(grep "Private key:" "$bp_keys_file" | cut -d: -f2 | tr -d ' ')
  cleos wallet import --name network-wallet --private-key "$bp_private_key" 2>/dev/null || true
  
  echo "Registering BLS finalizer key..."
  if [[ -n "$proof_of_possession" ]]; then
    if cleos -u "$main_endpoint" push action eosio regfinalizer \
      "[\"$MINI_PRODUCER_NAME\", \"$bls_public_key\", \"$proof_of_possession\"]" \
      -p "$MINI_PRODUCER_NAME" 2>/dev/null; then
      echo "✅ BLS finalizer registered successfully"
    else
      echo "⚠️  Finalizer registration failed (may already be registered)"
    fi
  else
    echo "⚠️  No proof of possession found - cannot register finalizer"
    echo "   Regenerate BLS keys with: spring-util bls create key --to-console"
  fi
  
  return 0
}

check_producer_status() {
  local main_endpoint="$MAIN_NET_API"
  
  echo "🔍 Checking mini producer status on ${main_endpoint}..."
  
  if ! cleos -u "$main_endpoint" get info >/dev/null 2>&1; then
    echo "❌ Cannot connect to main network at $main_endpoint"
    return 1
  fi
  
  if ! cleos -u "$main_endpoint" get account "$MINI_PRODUCER_NAME" >/dev/null 2>&1; then
    echo "❌ Account $MINI_PRODUCER_NAME does not exist"
    echo "   Run: $0 register"
    return 1
  fi
  
  echo "✅ Account exists: $MINI_PRODUCER_NAME"
  
  producer_info=$(cleos -u "$main_endpoint" system listproducers -l 1000 2>/dev/null | grep "^$MINI_PRODUCER_NAME" || echo "")
  if [[ -n "$producer_info" ]]; then
    echo "✅ Producer registered:"
    echo "   $producer_info"
    
    active_position=$(cleos -u "$main_endpoint" system listproducers -l 21 2>/dev/null | grep -n "^$MINI_PRODUCER_NAME" | cut -d: -f1 || echo "")
    if [[ -n "$active_position" ]]; then
      echo "🎉 Producer is ACTIVE (position #$active_position)"
    else
      echo "⚠️  Producer is registered but not in top 21 active producers"
    fi
  else
    echo "❌ Producer not registered"
    echo "   Run: $0 register"
    return 1
  fi
  
  if [[ -n "${VOTER_ACCOUNT:-}" ]]; then
    vote_info=$(cleos -u "$main_endpoint" get table eosio eosio voters -l 1000 2>/dev/null | jq -r ".rows[] | select(.owner==\"$VOTER_ACCOUNT\") | .producers[]" 2>/dev/null || echo "")
    if echo "$vote_info" | grep -q "^$MINI_PRODUCER_NAME$"; then
      echo "✅ Voter account $VOTER_ACCOUNT is voting for mini producer"
    else
      echo "⚠️  Voter account $VOTER_ACCOUNT is not voting for mini producer"
    fi
  fi
  
  echo ""
  echo "🔐 BLS Finalizer Status:"
  finalizer_info=$(cleos -u "$main_endpoint" get table eosio eosio finalizers -l 1000 2>/dev/null | jq -r ".rows[] | select(.producer_name==\"$MINI_PRODUCER_NAME\")" 2>/dev/null || echo "")
  if [[ -n "$finalizer_info" ]]; then
    echo "✅ BLS finalizer registered (Savanna consensus ready)"
    bls_key=$(echo "$finalizer_info" | jq -r '.public_key' 2>/dev/null || echo "")
    if [[ -n "$bls_key" && "$bls_key" != "null" ]]; then
      echo "   BLS Public Key: ${bls_key:0:20}..."
    fi
  else
    echo "❌ BLS finalizer not registered"
    echo "   Run: $0 register (to register finalizer)"
  fi
  
  return 0
}

create_configs() {
  echo "Creating mini network configurations..."
  
  mkdir -p "${MINI_CONFIG_ROOT}"/{bp-lite,api-node}
  
  # Handle BP keys (existing or new)
  local bp_keys_file="${MINI_CONFIG_ROOT}/bp-lite/keys.txt"
  local bp_bls_keys_file="${MINI_CONFIG_ROOT}/bp-lite/bls_finalizer.key"
  
  if [[ -n "$EXISTING_BP_ACCOUNT" && -n "$EXISTING_BP_PRIVATE_KEY" && -n "$EXISTING_BP_PUBLIC_KEY" ]]; then
    echo "Using existing BP account: $EXISTING_BP_ACCOUNT"
    MINI_PRODUCER_NAME="$EXISTING_BP_ACCOUNT"
    cat > "$bp_keys_file" << EOF
Private key: $EXISTING_BP_PRIVATE_KEY
Public key: $EXISTING_BP_PUBLIC_KEY
EOF
  else
    echo "Generating new BP keys..."
    if [[ ! -f "$bp_keys_file" ]]; then
      cleos create key --to-console > "$bp_keys_file"
    fi
  fi
  
  # Generate BLS finalizer keys for BP
  if [[ ! -f "$bp_bls_keys_file" ]]; then
    echo "Generating BLS finalizer keys for BP..."
    if command -v spring-util >/dev/null 2>&1; then
      spring-util bls create key --to-console > "$bp_bls_keys_file"
    else
      echo "⚠️  spring-util not found. BLS keys not generated."
      touch "$bp_bls_keys_file"
    fi
  fi
  
  # Generate API node keys
  local api_keys_file="${MINI_CONFIG_ROOT}/api-node/keys.txt"
  if [[ ! -f "$api_keys_file" ]]; then
    echo "Generating API node keys..."
    cleos create key --to-console > "$api_keys_file"
  fi

  # Extract BLS keys if available
  local bls_public_key="" bls_private_key=""
  if [[ -f "$bp_bls_keys_file" && -s "$bp_bls_keys_file" ]]; then
    bls_public_key=$(grep "Public key:" "$bp_bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
    bls_private_key=$(grep "Private key:" "$bp_bls_keys_file" | cut -d: -f2 | tr -d ' ' || echo "")
  fi

  # BP-Lite config (light producer with LIMITED history)
  cat > "${MINI_CONFIG_ROOT}/bp-lite/config.ini" << EOF
# Light Block Producer Configuration (LIMITED HISTORY)
chain-state-db-size-mb = ${MINI_BP_CHAIN_STATE_DB_SIZE}
chain-state-db-guard-size-mb = $((MINI_BP_CHAIN_STATE_DB_SIZE / 8))
reversible-blocks-db-size-mb = 340
reversible-blocks-db-guard-size-mb = 34
p2p-server-address = 0.0.0.0:${MINI_BP_P2P_PORT}
plugin = eosio::chain_plugin
plugin = eosio::chain_api_plugin
plugin = eosio::http_plugin
plugin = eosio::producer_plugin
plugin = eosio::producer_api_plugin
plugin = eosio::net_plugin
plugin = eosio::net_api_plugin
eos-vm-oc-enable = true
chain-threads = ${MINI_CHAIN_THREADS}
http-threads = ${MINI_HTTP_THREADS}
net-threads = ${MINI_NET_THREADS}
enable-stale-production = true
producer-name = ${MINI_PRODUCER_NAME}
max-retained-block-files = ${MINI_BP_BLOCK_HISTORY_LIMIT}
http-validate-host = false
access-control-allow-origin = *
verbose-http-errors = true
allowed-connection = ${MINI_ALLOWED_CONNECTIONS}
p2p-max-nodes-per-host = ${MINI_MAX_NODES_PER_HOST}
EOF

  # Add mandatory main network peers to BP-Lite
  if [[ ${#MAIN_NETWORK_P2P_PEERS[@]} -gt 0 ]]; then
    echo "" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    echo "# Connection to main network" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    for peer in "${MAIN_NETWORK_P2P_PEERS[@]}"; do
      echo "p2p-peer-address = ${peer}" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    done
  fi

  # Add additional peers to BP-Lite
  if [[ ${#ADDITIONAL_P2P_PEERS[@]} -gt 0 ]]; then
    echo "" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    echo "# Additional P2P Connections" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    for peer in "${ADDITIONAL_P2P_PEERS[@]}"; do
      echo "p2p-peer-address = ${peer}" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    done
  fi

  if [[ -n "$bls_public_key" && -n "$bls_private_key" ]]; then
    echo "" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    echo "# BLS Finalizer Key (Spring/Savanna consensus)" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
    echo "signature-provider = ${bls_public_key}=KEY:${bls_private_key}" >> "${MINI_CONFIG_ROOT}/bp-lite/config.ini"
  fi

  # API Node config (full API + state history with UNLIMITED history)
  cat > "${MINI_CONFIG_ROOT}/api-node/config.ini" << EOF
# API + State History Node Configuration (UNLIMITED HISTORY)
chain-state-db-size-mb = ${MINI_API_CHAIN_STATE_DB_SIZE}
chain-state-db-guard-size-mb = $((MINI_API_CHAIN_STATE_DB_SIZE / 8))
p2p-server-address = 0.0.0.0:${MINI_API_P2P_PORT}
plugin = eosio::chain_plugin
plugin = eosio::chain_api_plugin
plugin = eosio::http_plugin
plugin = eosio::net_plugin
plugin = eosio::net_api_plugin
plugin = eosio::db_size_api_plugin
plugin = eosio::state_history_plugin
state-history-endpoint = 0.0.0.0:${MINI_STATE_HISTORY_PORT}
trace-history = true
chain-state-history = true
max-retained-block-files = ${MINI_API_BLOCK_HISTORY_LIMIT}
enable-account-queries = true
http-validate-host = false
access-control-allow-origin = *
verbose-http-errors = true
eos-vm-oc-enable = true
allowed-connection = ${MINI_ALLOWED_CONNECTIONS}
p2p-max-nodes-per-host = ${MINI_MAX_NODES_PER_HOST}
chain-threads = ${MINI_CHAIN_THREADS}
http-threads = ${MINI_HTTP_THREADS}
net-threads = ${MINI_NET_THREADS}
producer-name = 
EOF

  # Add mandatory main network peers to API-Node
  if [[ ${#MAIN_NETWORK_P2P_PEERS[@]} -gt 0 ]]; then
    echo "" >> "${MINI_CONFIG_ROOT}/api-node/config.ini"
    echo "# Connection to main network" >> "${MINI_CONFIG_ROOT}/api-node/config.ini"
    for peer in "${MAIN_NETWORK_P2P_PEERS[@]}"; do
      echo "p2p-peer-address = ${peer}" >> "${MINI_CONFIG_ROOT}/api-node/config.ini"
    done
  fi

  # Add additional peers to API-Node
  if [[ ${#ADDITIONAL_P2P_PEERS[@]} -gt 0 ]]; then
    echo "" >> "${MINI_CONFIG_ROOT}/api-node/config.ini"
    echo "# Additional P2P Connections" >> "${MINI_CONFIG_ROOT}/api-node/config.ini"
    for peer in "${ADDITIONAL_P2P_PEERS[@]}"; do
      echo "p2p-peer-address = ${peer}" >> "${MINI_CONFIG_ROOT}/api-node/config.ini"
    done
  fi

  echo "✅ Configurations created in ${MINI_CONFIG_ROOT}"
  echo ""
  echo "Endpoints (accessible remotely):"
  echo "  BP-Lite:       http://0.0.0.0:${MINI_BP_HTTP_PORT} (P2P: ${MINI_BP_P2P_PORT})"
  echo "  API Node:      http://0.0.0.0:${MINI_API_HTTP_PORT} (P2P: ${MINI_API_P2P_PORT})"
  echo "  State History: ws://0.0.0.0:${MINI_STATE_HISTORY_PORT}"
  echo ""
  
  if [[ -n "$EXISTING_BP_ACCOUNT" && "$EXISTING_BP_ACCOUNT" != "null" ]]; then
    echo "📋 Using existing BP account: $EXISTING_BP_ACCOUNT"
    echo "   BLS finalizer keys generated for Savanna consensus"
  else
    echo "🔑 New BP account will be created: $MINI_PRODUCER_NAME"
    echo "   Both EOSIO and BLS keys generated"
  fi
  
  echo ""
  echo "📝 To use an existing BP account, edit config/mini_network.yaml"
  echo "   and set existing_bp fields."
  echo ""
  echo "📝 Other customizations:"
  echo "   - Main network peers under main_network.p2p_peers"
}

print_info() {
  echo ""
  echo "=== Mini Network Info ==="
  echo "BP-Lite:     http://0.0.0.0:${MINI_BP_HTTP_PORT} (Limited history)"
  echo "API Node:    http://0.0.0.0:${MINI_API_HTTP_PORT} (Full history)"
  echo "State Hist:  ws://0.0.0.0:${MINI_STATE_HISTORY_PORT} (for indexers)"
  echo "Data:        ${MINI_ROOT}"
  echo "Configs:     ${MINI_CONFIG_ROOT}"
  echo "Main Net Peers: ${#MAIN_NETWORK_P2P_PEERS[@]} configured"
  for peer in "${MAIN_NETWORK_P2P_PEERS[@]}"; do
    echo "             -> ${peer}"
  done
  if [[ ${#ADDITIONAL_P2P_PEERS[@]} -gt 0 ]]; then
    echo "Addt'l Peers: ${#ADDITIONAL_P2P_PEERS[@]} configured"
    for peer in "${ADDITIONAL_P2P_PEERS[@]}"; do
      echo "             -> ${peer}"
    done
  fi
  echo "========================="
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
case "${1:-}" in
  create)
    create_configs
    echo ""
    if [[ -n "$EXISTING_BP_ACCOUNT" && "$EXISTING_BP_ACCOUNT" != "null" ]]; then
      echo "🔧 Configs created for existing BP. Next steps:"
      echo "   $0 finalizer  # Register BLS finalizer keys"
      echo "   $0 start      # Launch nodes"
    else
      echo "🔧 Configs created for new BP. Next steps:"
      echo "   $0 register   # Register BP + finalizer on network"
      echo "   $0 start      # Launch nodes"
    fi
    ;;
  register)
    register_producer
    ;;
  finalizer)
    check_finalizer_registration
    ;;
  check)
    check_producer_status
    ;;
  start)
    if [[ ! -d "$MINI_CONFIG_ROOT" ]]; then
      echo "❌ Configs not found. Run: $0 create"
      exit 1
    fi
    for spec in "${NODES[@]}"; do start_node "$spec"; done
    print_info
    ;;
  stop)
    for spec in "${NODES[@]}"; do stop_node "$spec"; done
    ;;
  restart)
    "$0" stop && sleep 2 && "$0" start
    ;;
  status)
    for spec in "${NODES[@]}"; do print_status "$spec"; done
    print_info
    echo ""
    echo "🔍 Producer Registration:"
    check_producer_status
    ;;
  start-bp)
    if [[ ! -d "$MINI_CONFIG_ROOT" ]]; then
      echo "❌ Configs not found. Run: $0 create"
      exit 1
    fi
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ _ _ _ <<<"$spec"
      if [[ "$name" == "bp-lite" ]]; then
        start_node "$spec"
        break
      fi
    done
    print_info
    ;;
  start-api)
    if [[ ! -d "$MINI_CONFIG_ROOT" ]]; then
      echo "❌ Configs not found. Run: $0 create"
      exit 1
    fi
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ _ _ _ <<<"$spec"
      if [[ "$name" == "api-node" ]]; then
        start_node "$spec"
        break
      fi
    done
    print_info
    ;;
  stop-bp)
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ _ _ _ <<<"$spec"
      if [[ "$name" == "bp-lite" ]]; then
        stop_node "$spec"
        break
      fi
    done
    ;;
  stop-api)
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ _ _ _ <<<"$spec"
      if [[ "$name" == "api-node" ]]; then
        stop_node "$spec"
        break
      fi
    done
    ;;
  status-bp)
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ _ _ _ <<<"$spec"
      if [[ "$name" == "bp-lite" ]]; then
        print_status "$spec"
        break
      fi
    done
    ;;
  status-api)
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ _ _ _ <<<"$spec"
      if [[ "$name" == "api-node" ]]; then
        print_status "$spec"
        break
      fi
    done
    ;;
  restart-bp)
    "$0" stop-bp && sleep 2 && "$0" start-bp
    ;;
  restart-api)
    "$0" stop-api && sleep 2 && "$0" start-api
    ;;
  logs)
    echo "=== Node Log Management ==="
    for spec in "${NODES[@]}"; do
      IFS='|' read -r name _ data _ _ <<<"$spec"
      log_file="$data/logs/nodeos.log"
      if [[ -f "$log_file" ]]; then
        log_size_mb=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
        log_size_mb=$((log_size_mb / 1024 / 1024))
        echo "[$name] Log size: ${log_size_mb}MB"
        
        if [[ $log_size_mb -gt 100 ]]; then
          echo "[$name] ⚠️  Log over 100MB limit, truncating..."
          rotate_logs_if_needed "$data" "$name"
        else
          echo "[$name] ✅ Log size OK"
        fi
      else
        echo "[$name] No log file found"
      fi
      echo ""
    done
    ;;
  *)
    echo "Usage: $0 {create|register|finalizer|check|start|stop|restart|status|logs|start-bp|start-api|stop-bp|stop-api|restart-bp|restart-api|status-bp|status-api}"
    echo ""
    echo "Main Commands:"
    echo "  create    - Setup configs and generate keys (EOSIO + BLS)"
    echo "  register  - Register mini BP on main network"
    echo "  finalizer - Register BLS finalizer keys only"
    echo "  check     - Check mini BP registration status"
    echo ""
    echo "Node Management (Both):"
    echo "  start     - Launch both nodes" 
    echo "  stop      - Stop both nodes"
    echo "  restart   - Restart both nodes"
    echo "  status    - Show status of both nodes"
    echo "  logs      - Check/truncate log files (100MB limit)"
    echo ""
    echo "Individual Node Management:"
    echo "  start-bp    - Start only block producer"
    echo "  start-api   - Start only API node"
    echo "  stop-bp     - Stop only block producer"
    echo "  stop-api    - Stop only API node"
    echo "  restart-bp  - Restart only block producer"
    echo "  restart-api - Restart only API node"
    echo "  status-bp   - Status of block producer only"
    echo "  status-api  - Status of API node only"
    echo ""
    echo "First-time setup (new BP):"
    echo "  1. $0 create     # Generate configs and keys"
    echo "  2. $0 register   # Register BP on main network" 
    echo "  3. $0 check      # Verify registration"
    echo "  4. $0 start      # Launch nodes"
    echo ""
    echo "Existing BP setup:"
    echo "  1. Edit config/mini_network.yaml (set existing_bp fields)"
    echo "  2. $0 create     # Generate BLS keys + configs"
    echo "  3. $0 finalizer  # Register BLS finalizer only"
    echo "  4. $0 start      # Launch nodes"
    exit 1
    ;;
esac