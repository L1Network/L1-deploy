# L1 Network Setup Scripts

This repository contains scripts for setting up and managing an L1 blockchain based on AntelopeIO technology. Below is an overview of the available scripts and their purposes.
Most of the scripts are based on the repo: https://github.com/eosnetworkfoundation/bootstrap-private-network

## Overview

### Core Configuration
- **config.sh**: Central configuration file containing environment variables, account names, and parameters used by other scripts.

### Network Management
- **network_control.sh**: Main controller script that orchestrates the entire network setup process, including node startup, account creation, contract deployment, and system activation.
- **get_info.sh**: Utility to fetch and display information about the blockchain, including node status, account details, system resources, and permission structures.
- **open_wallet.sh**: Creates and unlocks the blockchain wallet to enable transaction signing.

### Account Setup
- **create_accounts.sh**: Creates system and user accounts required by the blockchain.
- **block_producer_setup.sh**: Configures block producer accounts, registers them as producers, and sets up voting.
- **tranfer_permissions.sh**: Transfers control of system accounts (including eosio) to a designated voter account for governance purposes.

### Contract Deployment
- **boot_actions.sh**: Initializes the blockchain by activating features, creating system accounts, and deploying core contracts.
- **deploy_bitcash_contracts.sh**: Deploys specialized BitCash contracts to the blockchain.

### Protocol Features
- **activate_savanna.sh**: Activates the Savanna consensus protocol, enabling instant finality for transactions.

## Detailed Workflow (`network_control.sh CREATE`)

The `CREATE` command initializes a new blockchain network from scratch. Here's a detailed breakdown of the steps involved:

1.  **Initialization & Pre-checks**:
    *   Loads configuration variables from `bin/config.sh`.
    *   Checks if there's sufficient disk space in the specified `ROOT_DIR`. If space is below a threshold (90%), the script exits.

2.  **Key Generation**:
    *   Creates the wallet directory (`WALLET_DIR`) if it doesn't exist.
    *   Generates initial EOSIO key pair (`network.keys`) used for bootstrapping the chain, if not already present.
    *   Generates standard EOSIO key pairs for each block producer defined in `config.sh` (`<producer_name>.keys`), if not already present.

3.  **Genesis & Node Configuration**:
    *   Creates the `genesis.json` file in `ROOT_DIR` by updating a template (`$GENESIS_FILE`) with the initial EOSIO public key and the current timestamp.
    *   Creates necessary directories for logs (`LOG_DIR`) and data for each node (`$ROOT_DIR/$NODE_ONE_DIR/data`, etc.).
    *   Copies the base `config.ini` and `logging.json` templates into `ROOT_DIR`.

4.  **Wallet Setup**:
    *   Executes `bin/open_wallet.sh`: This creates the `network-wallet` (if needed) and ensures it's unlocked.
    *   Imports the initial EOSIO private key into `network-wallet`.

5.  **Initial Chain Bootstrap (Temporary Node)**:
    *   Starts the first node (`Node One`) using the `genesis.json` file. This node initially runs using the `eosio` account and key (`--producer-name eosio`, `--signature-provider ...`). This is a temporary setup required to perform initial system actions.
    *   **Executes `bin/boot_actions.sh`**: This crucial script performs the very first on-chain actions:
        *   Creates essential system accounts (like `eosio.msig`, `eosio.token`, `eosio.ram`, `eosio.stake`, etc.).
        *   Deploys foundational system contracts (`eosio.token`, `eosio.msig`, `eosio.wrap`, `eosio.boot`, `eosio.system`).
        *   Activates numerous required protocol features, enabling advanced blockchain functionalities.
        *   Initializes the system contract (`eosio.system::init`).
    *   **Executes `bin/create_accounts.sh`**: Creates user accounts and potentially stakes initial CPU/NET resources for producers and users as defined in `config.sh`.
    *   **Executes `bin/block_producer_setup.sh`**:
        *   Imports the producer keys (generated in step 2) into the wallet.
        *   Registers each producer account on-chain (`cleos system regproducer`).
        *   Sets up voting: The designated `$VOTER_ACCOUNT` (from `config.sh`) casts votes for all registered producers.
    *   **Shuts Down Temporary Node**: After the initial setup actions, the temporary `eosio`-controlled node is stopped (`kill -15`). This is necessary because the chain must now be run by the actual registered block producers.

6.  **Restart Nodes with Producer Keys**:
    *   **Node One**: Restarts using its assigned producer name (`${PRODUCERS[0]}`) and corresponding keys. It's configured to connect to the other nodes via P2P.
    *   **Node Two**: Starts using its assigned producer name (`${PRODUCERS[1]}`) and keys, connecting via P2P.
    *   **Node Three**: Starts using its assigned producer name (`${PRODUCERS[2]}`) and keys, connecting via P2P.
    *   A short wait period allows the nodes to start and begin synchronizing.

7.  **Savanna Consensus Activation**:
    *   **BLS Key Generation**: Generates new BLS key pairs (required for Savanna finality) for each producer using `spring-util`. These keys are stored securely:
        *   Public/Private/Proof-of-Possession keys are saved to `<producer_name>.finalizer.key` files in `WALLET_DIR`.
        *   Sensitive private keys are moved out of `bin/config.sh` and stored in a separate, permission-restricted script (`$ROOT_DIR/secure/bls_keys.sh`). `bin/config.sh` is updated to reference this secure file.
        *   The `config.ini` in `ROOT_DIR` is updated to include the BLS public/private key pairs as signature providers for `nodeos`.
    *   **Node Restart**: All three nodes are stopped and then restarted using `start_func "START"`. This forces them to load the updated `config.ini` containing the necessary BLS keys.
    *   **On-Chain Activation**: Executes `bin/activate_savanna.sh`. This script performs the on-chain transactions required to formally activate the Savanna consensus protocol features using the loaded BLS keys.
    *   **Verification**: Waits and checks node logs to confirm the transition to Savanna ("Transitioning to savanna", "Transition to instant finality").

8.  **Final Governance Setup**:
    *   **Executes `bin/tranfer_permissions.sh`**: This script changes the `active` and `owner` permissions of all core system accounts (including `eosio`, `eosio.ram`, `eosio.stake`, etc.) to be controlled by the `$VOTER_ACCOUNT`'s `active` permission. This centralizes system control under the designated governance account.

9.  **Completion**: The script prints "COMPLETED COMMAND CREATE", indicating the successful creation and initialization of the network.

## Other Commands (`network_control.sh`)

Besides `CREATE`, the `network_control.sh` script accepts the following commands:

### `START`

*   **Purpose**: Starts an existing blockchain network that has already been created (using `CREATE`) but is currently stopped.
*   **Actions**:
    1.  **Pre-checks**: Checks for sufficient disk space.
    2.  **Wallet**: Opens and unlocks the `network-wallet` using `bin/open_wallet.sh`. It assumes keys (network key, producer keys) are already generated and present.
    3.  **Node Startup**: Starts the three `nodeos` instances (Node One, Node Two, Node Three) using their respective producer names and keys defined in `config.sh` and wallet. Nodes are configured to peer with each other.
    4.  **No Initialization**: Unlike `CREATE`, this command does *not* run `boot_actions.sh`, `create_accounts.sh`, `block_producer_setup.sh`, `activate_savanna.sh`, or `tranfer_permissions.sh`. It assumes the chain state and configuration already exist in the node data directories.

### `STOP`

*   **Purpose**: Stops all running `nodeos` processes associated with the network.
*   **Actions**:
    1.  Identifies all `nodeos` processes running under the current user ID.
    2.  Sends a `SIGTERM` signal (kill -15) to each identified `nodeos` process, allowing for a graceful shutdown.
    3.  Waits briefly for the processes to terminate.

### `CLEAN`

*   **Purpose**: Stops the network and completely wipes all blockchain data and logs, resetting the environment for a fresh `CREATE`. **Use with caution!**
*   **Actions**:
    1.  **Stop Nodes**: Executes the `STOP` command logic to shut down any running `nodeos` instances.
    2.  **Wipe Data**: Deletes all contents within the `ROOT_DIR` directory defined in `config.sh`. This includes node data directories, logs, `genesis.json`, `config.ini`, etc.
    3.  **Recreate Structure**: Recreates the basic directory structure (`$ROOT_DIR/nodeX/data`, `$LOG_DIR`) needed for a subsequent `CREATE` command.
