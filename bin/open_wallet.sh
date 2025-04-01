#!/usr/bin/env bash

####
# Used to open wallet to store key
# needed to create accounts, activate features, and create contracts
# called from finality_test_network.sh
####

WALLET_DIR=$1

# setup wallets, open wallet, add keys if needed
[ ! -d "$WALLET_DIR" ] && mkdir -p "$WALLET_DIR"
if [ ! -f "${WALLET_DIR}"/network-wallet.wallet ]; then
  cleos wallet create --name network-wallet --file "${WALLET_DIR}"/network-wallet.pw
fi
IS_WALLET_OPEN=$(cleos wallet list | grep network-wallet | grep -F '*' | wc -l)
# not open then it is locked so unlock it
if [ $IS_WALLET_OPEN -lt 1 ]; then
  cat "${WALLET_DIR}"/network-wallet.pw | cleos wallet unlock --name network-wallet --password
fi
