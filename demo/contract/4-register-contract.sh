#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set -ex

CONTRACT_SERVICE_URL=${CONTRACT_SERVICE_URL:-"https://127.0.0.1:8000"}
TRUST_STORE=/tmp/trust_store

TMP_DIR=/tmp/$TDP_USERNAME

scitt submit-contract $TMP_DIR/contract.cose \
    --receipt $TMP_DIR/contract.receipt.cbor \
    --url $CONTRACT_SERVICE_URL \
    --service-trust-store $TRUST_STORE \
    --development
