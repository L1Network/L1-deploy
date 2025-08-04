# L1 Network Deployment Suite

This repository contains a comprehensive suite of scripts for deploying and managing AntelopeIO-based blockchain networks. It provides two primary systems: a full **Main Network** for production-like environments and a lightweight **Mini Network** for development and testing that connects to an existing chain.

## ✨ Latest Features

- **🚀 Snapshot Support**: Fast blockchain sync using snapshots with YAML-configured sources
- **📝 Smart Log Management**: Automatic 100MB log rotation with zero downtime
- **⛓️ IMPACT Genesis Integration**: Native support for IMPACT Layer 1 network
- **⚙️ Enhanced Configuration**: Comprehensive YAML-based configuration management

## Table of Contents
1.  [Overview](#overview)
2.  [Prerequisites](#prerequisites)
3.  [Main Network Setup (`network_control.sh`)](#main-network-setup-network_controlsh)
    *   [Configuration](#main-network-configuration)
    *   [Commands](#main-network-commands)
    *   [Workflow](#main-network-workflow)
4.  [Mini Network Setup (`mini_network_control.sh`)](#mini-network-setup-mini_network_controlsh)
    *   [Configuration](#mini-network-configuration)
    *   [Commands](#mini-network-commands)
    *   [Workflow](#mini-network-workflow)
5.  [Contract Deployment](#contract-deployment)
6.  [Core Scripts Reference](#core-scripts-reference)

---

## Overview

-   **Main Network**: A complete, 3-node production-style network created from a genesis state. Managed by `bin/network_control.sh`.
-   **Mini Network**: A 2-node (BP + API) lightweight network that syncs with an existing blockchain (like the Main Network). Managed by `bin/mini_network_control.sh`. It features differentiated block history between nodes.

---

## Prerequisites

-   An Antelope-based `nodeos` binary in your `$PATH`.
-   `cleos` for interacting with the blockchain.
-   `yq` for parsing YAML configuration (`brew install yq` or `apt-get install yq`).
-   (Optional) `spring-util` for generating BLS keys for Savanna consensus.

---

## Main Network Setup (`network_control.sh`)

This system creates a complete, standalone blockchain network.

### Main Network Configuration

Configuration is managed in `bin/config.sh`. Key variables include:
-   `ROOT_DIR`: The root directory for all chain data.
-   `PRODUCERS`: An array of producer account names.
-   `VOTER_ACCOUNT`: The account responsible for governance and voting.

### Main Network Commands

| Command | Description                                                |
| :------ | :--------------------------------------------------------- |
| `CREATE`  | Initializes a new 3-node network from genesis.           |
| `START`   | Starts the existing 3-node network.                        |
| `STOP`    | Stops all `nodeos` processes for the network.            |
| `CLEAN`   | **Deletes all chain data**. Resets the environment.      |

### Main Network Workflow

1.  **`./bin/network_control.sh CREATE`**:
    *   Generates EOSIO and BLS keys.
    *   Creates a `genesis.json`.
    *   Bootstraps a temporary node to set system contracts and create accounts.
    *   Restarts all three nodes as registered block producers.
    *   Activates Savanna consensus and finalizes governance permissions.

---

## Mini Network Setup (`mini_network_control.sh`)

This system runs a lightweight, 2-node network that connects to and syncs from an existing blockchain.

### Mini Network Configuration

Configuration is managed in `config/mini_network.yaml`. This comprehensive YAML file includes:

#### **Core Network Settings**
-   **`main_network.api_endpoint`**: The HTTP endpoint of the main network for sending transactions (like registrations).
-   **`main_network.p2p_peers`**: An array of `host:port` addresses for the main network nodes to sync from.
-   **Node Resources**: Differentiated settings for the `bp-lite` and `api-node`, including memory (`chain_state_db_size`) and block history limits (`block_history_limit`).

#### **Snapshot Configuration** 🚀
```yaml
snapshots:
  download_dir: "/data/snapshots"        # Where to store downloaded snapshots
  keep_downloaded: true                  # Keep files after use (true/false)
  sources:
    impact_mainnet: "https://snapshots.impact.detroitledger.tech/latest.bin"
    # Add more snapshot sources as needed
```

#### **Genesis Configuration** ⛓️
- **`GENESIS_FILE_ACTIVE`**: Points to the correct genesis file (e.g., `genesis-IMPACT.json`)
- Intelligent genesis handling for fresh starts vs. restarts

**Key Feature**: The `bp-lite` node is configured with a limited block history (`block_history_limit > 0`), while the `api-node` is configured with unlimited history (`block_history_limit: 0`).

### Mini Network Commands

#### **Main Commands**
| Command       | Description                                                  |
| :------------ | :----------------------------------------------------------- |
| `create`      | Generates config files and keys for the two nodes.           |
| `register`    | Registers the `bp-lite` node as a producer on the main network. |
| `finalizer`   | Registers the BLS finalizer key on the main network.         |
| `check`       | Verifies the producer registration status on the main network. |

#### **Node Management (Both)**
| Command       | Description                                                  |
| :------------ | :----------------------------------------------------------- |
| `start`       | Starts both `bp-lite` and `api-node`.                        |
| `stop`        | Stops both nodes.                                            |
| `restart`     | Stops and then starts both nodes.                            |
| `status`      | Checks if both nodes are running.                            |
| `logs`        | Check/truncate log files (100MB limit) 📝                   |

#### **Snapshot Management** 🚀
| Command                       | Description                                          |
| :---------------------------- | :--------------------------------------------------- |
| `snapshot-bp <source>`        | Start BP from snapshot (clears existing data)       |
| `snapshot-api <source>`       | Start API from snapshot (clears existing data)      |
| `snapshot-both <source>`      | Start both nodes from snapshot (clears data)        |

**Snapshot Source Examples:**
```bash
# Use predefined source from YAML
./bin/mini_network_control.sh snapshot-both impact_mainnet

# Direct URL (auto-downloads to configured directory)  
./bin/mini_network_control.sh snapshot-bp https://example.com/snapshot.bin

# Local file path
./bin/mini_network_control.sh snapshot-api /data/snapshots/snapshot.bin
```

#### **Individual Node Management**
| Command       | Description                                                  |
| :------------ | :----------------------------------------------------------- |
| `start-bp`    | Starts only the block producer (`bp-lite`).                  |
| `start-api`   | Starts only the API node (`api-node`).                       |
| `stop-bp`     | Stops only the block producer.                               |
| `stop-api`    | Stops only the API node.                                     |
| `restart-bp`  | Restarts only the block producer.                            |
| `restart-api` | Restarts only the API node.                                  |
| `status-bp`   | Checks if only the block producer is running.                |
| `status-api`  | Checks if only the API node is running.                      |

### Mini Network Workflow

#### **First-time Setup (New BP)**
1.  **Configure `config/mini_network.yaml`**: Point it to your running Main Network's API and P2P endpoints.
2.  **`./bin/mini_network_control.sh create`**: Generates `config.ini` files and keys.
3.  **`./bin/mini_network_control.sh register`**: Registers the new BP on the main chain.
4.  **`./bin/mini_network_control.sh check`**: Verify registration status.
5.  **Choose sync method:**
   - **Fast sync**: `./bin/mini_network_control.sh snapshot-both impact_mainnet` ⚡
   - **Full sync**: `./bin/mini_network_control.sh start` (slower, from genesis)

#### **Existing BP Setup**
1.  **Edit `config/mini_network.yaml`**: Set existing BP account details.
2.  **`./bin/mini_network_control.sh create`**: Generate BLS keys and configs.
3.  **`./bin/mini_network_control.sh finalizer`**: Register BLS finalizer only.
4.  **`./bin/mini_network_control.sh snapshot-both impact_mainnet`**: Fast sync with snapshot.

#### **Log Management** 📝

- **Automatic**: Logs are checked and rotated on every node start/restart
- **Manual**: Use `./bin/mini_network_control.sh logs` to check sizes and rotate
- **Limit**: 100MB per log file (configurable)
- **Policy**: Simple truncation (no old logs kept by default)

---

## Advanced Features & Best Practices

### **Snapshot Management** 🚀

**Configure Multiple Sources**:
```yaml
snapshots:
  download_dir: "/data/snapshots"
  keep_downloaded: true
  sources:
    impact_mainnet: "https://snapshots.impact.detroitledger.tech/latest.bin"
    impact_backup: "https://backup.example.com/snapshot.bin"
    local_archive: "/mnt/storage/snapshots/daily.bin"
```

**Usage Patterns**:
```bash
# Fast recovery from latest snapshot
./bin/mini_network_control.sh snapshot-both impact_mainnet

# Use backup source if primary fails
./bin/mini_network_control.sh snapshot-both impact_backup

# BP only from snapshot, API from genesis  
./bin/mini_network_control.sh snapshot-bp impact_mainnet
./bin/mini_network_control.sh start-api
```

### **Monitoring & Health Checks** 📊

**Check Node Status**:
```bash
# Quick status check
./bin/mini_network_control.sh status

# Detailed node information
curl -s http://localhost:9889/v1/chain/get_info | jq

# Check sync progress (compare with main network)
curl -s https://layer1.eosusa.io/v1/chain/get_info | jq -r '.head_block_num'
curl -s http://localhost:9889/v1/chain/get_info | jq -r '.head_block_num'
```

**Log Monitoring**:
```bash
# Check log sizes and rotate if needed
./bin/mini_network_control.sh logs

# Watch live logs
tail -f /data/chain-data/mini/api-node/logs/nodeos.log

# Monitor both nodes simultaneously
multitail /data/chain-data/mini/bp-lite/logs/nodeos.log /data/chain-data/mini/api-node/logs/nodeos.log
```

### **Performance Optimization** ⚡

**Resource Allocation** (in `mini_network.yaml`):
```yaml
resources:
  bp_lite:
    chain_state_db_size: 4096      # MB - adjust based on available RAM
    block_history_limit: 100000    # Limited history for faster startup
  
  api_node:
    chain_state_db_size: 8192      # MB - larger for API workloads
    block_history_limit: 0         # Unlimited history for full API functionality

performance:
  chain_threads: 2                 # CPU cores for chain processing
  http_threads: 4                  # Threads for API requests
  net_threads: 2                   # Network processing threads
```

### **Troubleshooting** 🔧

**Common Issues**:

1. **Node won't start**:
   ```bash
   # Check log for errors
   tail -50 /data/chain-data/mini/bp-lite/logs/nodeos.log
   
   # Clear corrupted data and start from snapshot
   ./bin/mini_network_control.sh snapshot-bp impact_mainnet
   ```

2. **Sync stuck/slow**:
   ```bash
   # Check P2P connections
   curl -s http://localhost:9889/v1/net/connections | jq
   
   # Restart with fresh snapshot
   ./bin/mini_network_control.sh snapshot-both impact_mainnet
   ```

3. **High disk usage**:
   ```bash
   # Check log sizes
   ./bin/mini_network_control.sh logs
   
   # Monitor blockchain data growth
   du -sh /data/chain-data/mini/*/data
   ```

**Emergency Recovery**:
```bash
# Complete reset and fast recovery
./bin/mini_network_control.sh stop
rm -rf /data/chain-data/mini/*/data
./bin/mini_network_control.sh snapshot-both impact_mainnet
```

---

## Contract Deployment

-   **`deploy_bitcash_contracts.sh`**: A specialized script to deploy BitCash-related smart contracts. It can be pointed at any network (`-n local` or a custom alias).

---

## File Structure & Configuration

```
L1-deploy/
├── bin/
│   ├── mini_network_control.sh    # Main mini network management script
│   ├── network_control.sh         # Full network management script  
│   ├── config.sh                  # Environment configuration
│   └── [other utility scripts]
├── config/
│   ├── mini_network.yaml          # Mini network configuration (YAML)
│   ├── genesis.json               # Generic genesis file
│   ├── genesis-IMPACT.json        # IMPACT network genesis file
│   └── [generated configs]
```

## Core Scripts Reference

The following scripts are used by the controllers but can be run individually for specific tasks:

### **Main Network Scripts**
-   `activate_savanna.sh`: Activates Savanna consensus features.
-   `block_producer_setup.sh`: Registers producers and sets up voting.
-   `boot_actions.sh`: Deploys system contracts and creates system accounts.
-   `create_accounts.sh`: Creates user and system accounts.
-   `get_info.sh`: Fetches on-chain information.
-   `open_wallet.sh`: Creates and unlocks the `cleos` wallet.
-   `transfer_permissions.sh`: Sets up system account governance.

### **Mini Network Features**
-   **Log Management**: Automatic 100MB rotation, manual control via `logs` command
-   **Snapshot Support**: URL/file-based rapid sync with YAML configuration
-   **Genesis Handling**: Intelligent fresh-start vs restart detection
-   **HAProxy Integration**: Production-ready SSL endpoints
-   **IMPACT Network**: Native support for IMPACT Layer 1 blockchain

### **Configuration Management**
-   **YAML-based**: Comprehensive configuration in `config/mini_network.yaml`
-   **Environment Variables**: Core settings in `bin/config.sh`
-   **Auto-generation**: Node configs created dynamically based on YAML settings

---