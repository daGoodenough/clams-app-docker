#!/bin/bash

set -e
cd "$(dirname "$0")"

. ./defaults.env
. ./load_env.sh

NODE_ID=0
PORT=9735

# grab any modifications from the command line.
for i in "$@"; do
    case $i in
        --id=*)
            NODE_ID="${i#*=}"
            shift
        ;;
        --port=*)
            PORT="${i#*=}"
            shift
        ;;
        *)
        ;;
    esac
done

NODE_PUBKEY=$(bash -c "./lightning-cli.sh --id=$NODE_ID getinfo" | jq -r '.id')
echo "$NODE_PUBKEY@$DOMAIN_NAME:$PORT"
