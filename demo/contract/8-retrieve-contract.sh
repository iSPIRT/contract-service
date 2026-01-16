#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -ex

CONTRACT_SEQ_NO=$1
CONTRACT_SERVICE_URL=${CONTRACT_SERVICE_URL:-"https://127.0.0.1:8000"}
TRUST_STORE=/tmp/trust_store

TMP_DIR=/tmp/$TDC_USERNAME

scitt retrieve-contracts /tmp/contracts \
    --url $CONTRACT_SERVICE_URL \
    --service-trust-store $TRUST_STORE \
    --from $CONTRACT_SEQ_NO \
    --to $CONTRACT_SEQ_NO \
    --development
