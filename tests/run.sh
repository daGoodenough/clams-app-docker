#!/bin/bash

set -e
cd "$(dirname "$0")"

echo "==========================================="
echo "Running tests... one moment please!"
echo "==========================================="

echo "Testing the bitcoin-cli script"
./test_bitcoin-cli.sh 

echo "==========================================="

echo "Testing the lightning-cli script"
./test_lightning-cli.sh

echo "==========================================="

echo "Testing prism plugin"
./test_prism_plugin.sh


