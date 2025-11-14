#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -ex

TMP_DIR=/tmp/$TDP_USERNAME

echo "Signing contract..."

CONTENT_TYPE="application/json"

scitt sign-contract \
    --contract /tmp/contracts/contract.json \
    --content-type "$CONTENT_TYPE" \
    --did-doc $TMP_DIR/did.json \
    --key $TMP_DIR/key.pem \
    --feed "depa-training-scenario" \
    --participant-info "did:web:$TDP_USERNAME.github.io" \
    --participant-info "did:web:$TDC_USERNAME.github.io" \
    --out $TMP_DIR/contract.cose
