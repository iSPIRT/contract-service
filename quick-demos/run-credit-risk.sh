#!/bin/bash

# # 1. Remove any existing services
# ./docker/service-manager.sh remove

# # 2. Build the service
# export PLATFORM=virtual
# ./docker/build.sh
# ./docker/run-service.sh

# 3. Copy the contract template and update with environment variables
cp quick-demos/credit-risk-contract-template.json ./demo/contract/contract_template.json

export TDP_USERNAME=<tdp-username>
export TDC_USERNAME=<tdc-username>
export CCRP_USERNAME=<ccrp-username>
export AZURE_STORAGE_ACCOUNT_NAME=<storage-account-name>

export AZURE_KEYVAULT_ENDPOINT=<akv>.vault.azure.net
export CONTRACT_SERVICE_URL=https://<contract-service-url>:8000

export AZURE_BANK_A_CONTAINER_NAME=<bank-a-container-name>
export AZURE_BANK_B_CONTAINER_NAME=<bank-b-container-name>
export AZURE_BUREAU_CONTAINER_NAME=<bureau-container-name>
export AZURE_FINTECH_CONTAINER_NAME=<fintech-container-name>

envsubst < demo/contract/contract_template.json > demo/contract/contract.json
./demo/contract/update-contract.sh

# 4. Setup the environment

./demo/contract/0-install-cli.sh
source venv/bin/activate
./demo/contract/1-contract-setup.sh

# 5. Sign and register the contract
curl https://${TDP_USERNAME}.github.io/.well-known/did.json

./demo/contract/3-sign-contract.sh
./demo/contract/4-register-contract.sh > quick-demos/credit-risk-contract_registration_output.txt
./demo/contract/5-view-receipt.sh
./demo/contract/6-validate.sh

# extract the sequence number from the contract registration output. last two digits in the first line
SEQUENCE_NUMBER=$(grep -o '[0-9][0-9]' quick-demos/credit-risk-contract_registration_output.txt | head -n 1)
CONTRACT_SEQ_NO=$((SEQUENCE_NUMBER))
echo "Sequence number: $SEQUENCE_NUMBER"

# 6. Retrieve the contract and sign it as TDC
./demo/contract/8-retrieve-contract.sh $SEQUENCE_NUMBER
./demo/contract/9-sign-contract.sh $SEQUENCE_NUMBER
./demo/contract/10-register-contract.sh

rm -rf quick-demos/credit-risk-contract_registration_output.txt