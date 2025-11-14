#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -ex

TMP_DIR=/tmp/$TDC_USERNAME

echo "Signing contract..."

CONTENT_TYPE="application/cose"

scitt sign-contract \
    --contract /tmp/contracts/2.$1.cose \
    --content-type "$CONTENT_TYPE" \
    --did-doc $TMP_DIR/did.json \
    --key $TMP_DIR/key.pem \
    --out $TMP_DIR/contract.cose \
    --add-signature 
