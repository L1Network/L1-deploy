#!/usr/bin/env bash

####
# Once first nodeos is setup, running and producing blocks
# called from finality_Test_network.sh
# execute these commands to activate features
# create accounts, contracts: boot, system, and token
# fund with tokens
####

ENDPOINT=$1
CONTRACT_DIR=$2
PUBLIC_KEY=$3

cleos --url $ENDPOINT create account eosio eosio.msig $PUBLIC_KEY
cleos --url $ENDPOINT create account eosio eosio.ram $PUBLIC_KEY
cleos --url $ENDPOINT create account eosio eosio.ramfee $PUBLIC_KEY
cleos --url $ENDPOINT create account eosio eosio.stake $PUBLIC_KEY
cleos --url $ENDPOINT create account eosio eosio.token $PUBLIC_KEY
cleos --url $ENDPOINT create account eosio eosio.rex $PUBLIC_KEY
cleos --url $ENDPOINT create account eosio eosio.fees $PUBLIC_KEY

cleos --url $ENDPOINT set contract eosio.token "$CONTRACT_DIR"/eosio.token/
cleos --url $ENDPOINT push action eosio.token create '[ "eosio", "1000000000.0000 IMPACT" ]' -p eosio.token@active
cleos --url $ENDPOINT push action eosio.token issue '[ "eosio", "1000000000.0000 IMPACT", "initial issuance" ]' -p eosio
cleos --url $ENDPOINT set contract eosio.msig "$CONTRACT_DIR"/eosio.msig
cleos --url $ENDPOINT set contract eosio "$CONTRACT_DIR"/eosio.wrap

curl --request POST --url "$ENDPOINT"/v1/producer/schedule_protocol_feature_activations -d '{"protocol_features_to_activate": ["0ec7e080177b2c02b278d5088611686b49d739925a92d9bfcacd7fc6b74053bd"]}'
sleep 1
cleos --url $ENDPOINT set contract eosio "$CONTRACT_DIR"/eosio.boot/
# DISABLE_DEFERRED_TRXS_STAGE_1
cleos --url $ENDPOINT push action eosio activate '["fce57d2331667353a0eac6b4209b67b843a7262a848af0a49a6e2fa9f6584eb4"]' -p eosio
# DISABLE_DEFERRED_TRXS_STAGE_2
cleos --url $ENDPOINT push action eosio activate '["09e86cb0accf8d81c9e85d34bea4b925ae936626d00c984e4691186891f5bc16"]' -p eosio
# WTMSIG_BLOCK_SIGNATURES
cleos --url $ENDPOINT push action eosio activate '["299dcb6af692324b899b39f16d5a530a33062804e41f09dc97e9f156b4476707"]' -p eosio
# BLS_PRIMITIVES2
cleos --url $ENDPOINT push action eosio activate '["63320dd4a58212e4d32d1f58926b73ca33a247326c2a5e9fd39268d2384e011a"]' -p eosio
# DISALLOW_EMPTY_PRODUCER_SCHEDULE
cleos --url $ENDPOINT push action eosio activate '["68dcaa34c0517d19666e6b33add67351d8c5f69e999ca1e37931bc410a297428"]' -p eosio
# ACTION_RETURN_VALUE
cleos --url $ENDPOINT push action eosio activate '["c3a6138c5061cf291310887c0b5c71fcaffeab90d5deb50d3b9e687cead45071"]' -p eosio
# ONLY_LINK_TO_EXISTING_PERMISSION
cleos --url $ENDPOINT push action eosio activate '["1a99a59d87e06e09ec5b028a9cbb7749b4a5ad8819004365d02dc4379a8b7241"]' -p eosio
# FORWARD_SETCODE
cleos --url $ENDPOINT push action eosio activate '["2652f5f96006294109b3dd0bbde63693f55324af452b799ee137a81a905eed25"]' -p eosio
# GET_BLOCK_NUM
cleos --url $ENDPOINT push action eosio activate '["35c2186cc36f7bb4aeaf4487b36e57039ccf45a9136aa856a5d569ecca55ef2b"]' -p eosio
# REPLACE_DEFERRED
cleos --url $ENDPOINT push action eosio activate '["ef43112c6543b88db2283a2e077278c315ae2c84719a8b25f25cc88565fbea99"]' -p eosio
# NO_DUPLICATE_DEFERRED_ID
cleos --url $ENDPOINT push action eosio activate '["4a90c00d55454dc5b059055ca213579c6ea856967712a56017487886a4d4cc0f"]' -p eosio
# RAM_RESTRICTIONS
cleos --url $ENDPOINT push action eosio activate '["4e7bf348da00a945489b2a681749eb56f5de00b900014e137ddae39f48f69d67"]' -p eosio
# WEBAUTHN_KEY
cleos --url $ENDPOINT push action eosio activate '["4fca8bd82bbd181e714e283f83e1b45d95ca5af40fb89ad3977b653c448f78c2"]' -p eosio
# BLOCKCHAIN_PARAMETERS
cleos --url $ENDPOINT push action eosio activate '["5443fcf88330c586bc0e5f3dee10e7f63c76c00249c87fe4fbf7f38c082006b4"]' -p eosio
# CRYPTO_PRIMITIVES
cleos --url $ENDPOINT push action eosio activate '["6bcb40a24e49c26d0a60513b6aeb8551d264e4717f306b81a37a5afb3b47cedc"]' -p eosio
# ONLY_BILL_FIRST_AUTHORIZER
cleos --url $ENDPOINT push action eosio activate '["8ba52fe7a3956c5cd3a656a3174b931d3bb2abb45578befc59f283ecd816a405"]' -p eosio
# RESTRICT_ACTION_TO_SELF
cleos --url $ENDPOINT push action eosio activate '["ad9e3d8f650687709fd68f4b90b41f7d825a365b02c23a636cef88ac2ac00c43"]' -p eosio
# GET_CODE_HASH
cleos --url $ENDPOINT push action eosio activate '["bcd2a26394b36614fd4894241d3c451ab0f6fd110958c3423073621a70826e99"]' -p eosio
# CONFIGURABLE_WASM_LIMITS2
cleos --url $ENDPOINT push action eosio activate '["d528b9f6e9693f45ed277af93474fd473ce7d831dae2180cca35d907bd10cb40"]' -p eosio
# FIX_LINKAUTH_RESTRICTION
cleos --url $ENDPOINT push action eosio activate '["e0fb64b1085cc5538970158d05a009c24e276fb94e1a0bf6a528b48fbc4ff526"]' -p eosio
# GET_SENDER
cleos --url $ENDPOINT push action eosio activate '["f0af56d2c5a48d60a4a5b5c903edfb7db3a736a94ed589d0b797df33ff9d3e1d"]' -p eosio
# SAVANNA
# Depends on all other protocol features
cleos --url $ENDPOINT push action eosio activate '["cbe0fafc8fcc6cc998395e9b6de6ebd94644467b1b4a97ec126005df07013c52"]' -p eosio
sleep 1

cleos --url $ENDPOINT set contract eosio "$CONTRACT_DIR"/eosio.system
cleos --url $ENDPOINT push action eosio init '["0", "4,IMPACT"]' -p eosio@active
cleos --url $ENDPOINT push action eosio setpriv '["eosio.msig", 1]' -p eosio@active
sleep 1
# little test that everything has been setup correctly
cleos --url $ENDPOINT system buyram eosio eosio "1000 IMPACT"
