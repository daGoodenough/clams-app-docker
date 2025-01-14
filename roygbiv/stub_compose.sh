#!/bin/bash

set -e
cd "$(dirname "$0")"

# this script writes out the docker-compose.yml file.


names=(alice bob carol dave erin frank greg hannah ian jane kelly laura mario nick olivia)


# close HTTP block
DOCKER_COMPOSE_YML_PATH="$(pwd)/docker-compose.yml"
touch "$DOCKER_COMPOSE_YML_PATH"

# let's generate a random username and password and get our -rpcauth=<token>
BITCOIND_RPC_USERNAME=$(gpg --gen-random --armor 1 8 | tr -dc '[:alnum:]' | head -c10)
BITCOIND_RPC_PASSWORD=$(gpg --gen-random --armor 1 32 | tr -dc '[:alnum:]' | head -c32)
RPC_AUTH_TOKEN=$(./rpc-auth.py "$BITCOIND_RPC_USERNAME" "$BITCOIND_RPC_PASSWORD" | grep rpcauth)

BITCOIND_COMMAND="bitcoind -server=1 -${RPC_AUTH_TOKEN} -upnp=0 -rpcbind=0.0.0.0 -rpcallowip=0.0.0.0/0 -rpcport=${BITCOIND_RPC_PORT:-18443} -rest -listen=1 -listenonion=0 -fallbackfee=0.0002 -mempoolfullrbf=1 -prune=50000"

for CHAIN in regtest signet; do
    if [ "$CHAIN" = "$BTC_CHAIN" ]; then  
        BITCOIND_COMMAND="$BITCOIND_COMMAND -${BTC_CHAIN}" 
    fi
done

cat > "$DOCKER_COMPOSE_YML_PATH" <<EOF
version: '3.8'
services:

  reverse-proxy:
    image: nginx:latest
EOF


cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    ports:
      - 80:80
EOF

if [ "$ENABLE_TLS" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - 443:443
EOF
fi

# these are the ports for the websocket connections.
for (( CLN_ID=0; CLN_ID<CLN_COUNT; CLN_ID++ )); do
    CLN_WEBSOCKET_PORT=$(( STARTING_WEBSOCKET_PORT+CLN_ID ))
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - ${CLN_WEBSOCKET_PORT}:${CLN_WEBSOCKET_PORT}
EOF
done

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    networks:
EOF

for (( CLN_ID=0; CLN_ID<CLN_COUNT; CLN_ID++ )); do
    CLN_ALIAS="cln-${BTC_CHAIN}"
cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - clnnet-${CLN_ID}
EOF
done


if [ "$DEPLOY_PRISM_BROWSER_APP" = true ]; then
cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - prism-appnet
EOF
fi


cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    configs:
      - source: nginx-config
        target: /etc/nginx/nginx.conf
EOF

if [ "$DEPLOY_CLAMS_BROWSER_APP" = true ] || [ "$ENABLE_TLS" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    volumes:
EOF
fi

if [ "$DEPLOY_CLAMS_BROWSER_APP" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - clams-browser-app:/browser-app
EOF
fi

if [ "$ENABLE_TLS" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - certs:/certs
EOF
fi




if [ "$DEPLOY_PRISM_BROWSER_APP" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF

  prism-browser-app:
    image: ${PRISM_APP_IMAGE_NAME}
    networks:
      - prism-appnet
    environment:
      - HOST=0.0.0.0
      - PORT=5173
    command: >-
      npm run dev -- --host
    deploy:
      mode: global
EOF

fi


cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF

  bitcoind:
    image: ${BITCOIND_DOCKER_IMAGE_NAME}
    hostname: bitcoind
    networks:
      - bitcoindnet
    command: >-
      ${BITCOIND_COMMAND}
EOF

# we persist data for signet, testnet, and mainnet

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    volumes:
      - bitcoind-${BTC_CHAIN}:/home/bitcoin/.bitcoin
EOF


cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    deploy:
      mode: global

EOF

# write out service for CLN; style is a docker stack deploy style,
# so we will use the replication feature
for (( CLN_ID=0; CLN_ID<CLN_COUNT; CLN_ID++ )); do
    CLN_NAME="cln-${CLN_ID}"
    CLN_ALIAS=${names[$CLN_ID]}
    CLN_WEBSOCKET_PORT=$(( STARTING_WEBSOCKET_PORT+CLN_ID ))
    CLN_PTP_PORT=$(( STARTING_CLN_PTP_PORT+CLN_ID ))

    CLN_COMMAND="sh -c \"chown 1000:1000 /opt/c-lightning-rest/certs && lightningd --alias=${CLN_ALIAS} --bind-addr=0.0.0.0:9735 --announce-addr=${CLN_NAME}:9735 --announce-addr=${DOMAIN_NAME}:${CLN_PTP_PORT} --bitcoin-rpcuser=${BITCOIND_RPC_USERNAME} --bitcoin-rpcpassword=${BITCOIND_RPC_PASSWORD} --bitcoin-rpcconnect=bitcoind --bitcoin-rpcport=\${BITCOIND_RPC_PORT:-18443} --log-level=debug --dev-bitcoind-poll=20 --experimental-websocket-port=9736 --plugin=/opt/c-lightning-rest/plugin.js --plugin=/plugins/prism-plugin.py --experimental-offers"

    if [ "$BTC_CHAIN" != mainnet ]; then
        CLN_COMMAND="$CLN_COMMAND --network=${BTC_CHAIN}"
    fi

    CLN_COMMAND="$CLN_COMMAND\""
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  cln-${CLN_ID}:
    image: ${CLN_IMAGE}
    hostname: cln-${CLN_ID}
    command: >-
      ${CLN_COMMAND}
EOF

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    environment:
      - RPC_PATH=${RPC_PATH}
EOF

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    volumes:
      - cln-${CLN_ID}-${BTC_CHAIN}:/root/.lightning
      - cln-${CLN_ID}-certs-${BTC_CHAIN}:/opt/c-lightning-rest/certs
EOF

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    networks:
      - bitcoindnet
      - clnnet-${CLN_ID}
EOF


if [ "$BTC_CHAIN" = regtest ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
      - cln-p2pnet
EOF
fi

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    ports:
      - ${CLN_PTP_PORT}:9735
EOF

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
    deploy:
      mode: replicated
      replicas: 1

EOF

done

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
networks:
  bitcoindnet:
EOF

if [ "$BTC_CHAIN" = regtest ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  cln-p2pnet:
EOF
fi

for (( CLN_ID=0; CLN_ID<CLN_COUNT; CLN_ID++ )); do
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  clnnet-${CLN_ID}:
EOF

done


if [ "$DEPLOY_PRISM_BROWSER_APP" = true ]; then
cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  prism-appnet:
EOF
fi


cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF

volumes:
EOF

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF

  bitcoind-${BTC_CHAIN}:
EOF


# define the volumes for CLN nodes. regtest and signet SHOULD NOT persist data, but TESTNET and MAINNET MUST define volumes
for (( CLN_ID=0; CLN_ID<CLN_COUNT; CLN_ID++ )); do
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  cln-${CLN_ID}-${BTC_CHAIN}:
  cln-${CLN_ID}-certs-${BTC_CHAIN}:
EOF

done

if [ "$DEPLOY_CLAMS_BROWSER_APP" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF

  clams-browser-app:
    external: true
    name: clams-browser-app
EOF
fi

if [ "$ENABLE_TLS" = true ]; then
    cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF
  certs:
    external: true
    name: roygbiv-certs
EOF
fi

cat >> "$DOCKER_COMPOSE_YML_PATH" <<EOF

configs:
  nginx-config:
    file: ${NGINX_CONFIG_PATH}

EOF

