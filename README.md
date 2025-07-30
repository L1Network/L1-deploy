# L1 Network Deployment Suite

This repository contains a suite of scripts for deploying and managing AntelopeIO-based blockchain networks. It provides two primary systems: a full **Main Network** for production-like environments and a lightweight **Mini Network** for development and testing that connects to an existing chain.

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

Configuration is managed in `config/mini_network.yaml`. This file is crucial and requires you to define:
-   **`main_network.api_endpoint`**: The HTTP endpoint of the main network for sending transactions (like registrations).
-   **`main_network.p2p_peers`**: An array of `host:port` addresses for the main network nodes to sync from.
-   **Node Resources**: Differentiated settings for the `bp-lite` and `api-node`, including memory (`chain_state_db_size`) and block history limits (`block_history_limit`).

**Key Feature**: The `bp-lite` node is configured with a limited block history (`block_history_limit > 0`), while the `api-node` is configured with unlimited history (`block_history_limit: 0`).

### Mini Network Commands

| Command       | Description                                                  |
| :------------ | :----------------------------------------------------------- |
| `create`      | Generates config files and keys for the two nodes.           |
| `register`    | Registers the `bp-lite` node as a producer on the main network. |
| `finalizer`   | Registers the BLS finalizer key on the main network.         |
| `start`       | Starts both `bp-lite` and `api-node`.                        |
| `stop`        | Stops both nodes.                                            |
| `restart`     | Stops and then starts both nodes.                            |
| `status`      | Checks if both nodes are running.                            |
| `check`       | Verifies the producer registration status on the main network. |
| **Individual Node Management** | |
| `start-bp`    | Starts only the block producer (`bp-lite`).                  |
| `start-api`   | Starts only the API node (`api-node`).                       |
| `stop-bp`     | Stops only the block producer.                               |
| `stop-api`    | Stops only the API node.                                     |
| `restart-bp`  | Restarts only the block producer.                            |
| `restart-api` | Restarts only the API node.                                  |
| `status-bp`   | Checks if only the block producer is running.                |
| `status-api`  | Checks if only the API node is running.                      |

### Mini Network Workflow

1.  **Configure `config/mini_network.yaml`**: Point it to your running Main Network's API and P2P endpoints.
2.  **`./bin/mini_network_control.sh create`**: Generates `config.ini` files and keys.
3.  **`./bin/mini_network_control.sh register`**: Registers the new BP on the main chain.
4.  **`./bin/mini_network_control.sh start`**: Starts the two mini-nodes, which will begin syncing from the main network peers.

---

## Contract Deployment

-   **`deploy_bitcash_contracts.sh`**: A specialized script to deploy BitCash-related smart contracts. It can be pointed at any network (`-n local` or a custom alias).

---

## Core Scripts Reference

The following scripts are used by the controllers but can be run individually for specific tasks:
-   `activate_savanna.sh`: Activates Savanna consensus features.
-   `block_producer_setup.sh`: Registers producers and sets up voting.
-   `boot_actions.sh`: Deploys system contracts and creates system accounts.
-   `create_accounts.sh`: Creates user and system accounts.
-   `get_info.sh`: Fetches on-chain information.
-   `open_wallet.sh`: Creates and unlocks the `cleos` wallet.
-   `tranfer_permissions.sh`: Sets up system account governance.