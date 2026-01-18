# DEPA Training - Contract Signing Demo UI

A user-friendly web interface for demonstrating multi-party electronic contract signing for DEPA Training scenarios. Make sure you have completed the necessary steps on the [DEPA-Training](https://github.com/iSPIRT/depa-training) repo.

## Quick Start

From the project root directory, simply run:

```bash
./launch-demo.sh
```

Then open your browser to **http://localhost:5050**

By default, the demo connects to a live contract service at **https://216.48.178.54:8000**. You can change this in the UI configuration if you're running a local instance. If you encounter any issues with the live demo service, please contact the repository owners by opening an issue.

The demo contains steps for both the TDP and TDC to sign and register the contract. If you're using GitHub Codespaces to run this demo, make sure to use separate instances under the respective GitHub accounts for the TDP and TDC, when executing the contract signing steps specific to each. This ensures hassle-free authentication and avoids login conflicts.

## Features

### Scenario Selection
Choose from three pre-configured DEPA Training scenarios:
- **BraTS** - Brain tumor segmentation with 4 MRI dataset providers
- **COVID-19** - Healthcare data combining ICMR and CoWIN systems  
- **Credit Risk** - Multi-bank credit assessment collaboration

### Role-Based Workflow
The UI supports two roles that can be demonstrated:

#### Training Data Provider (TDP)
1. Setup contract template from scenario
2. Install CLI tools
3. Initialize contract service connection
4. Create DID (Decentralized Identifier) via GitHub Pages
5. Sign the contract
6. Register contract with the service
7. View receipt and validate

#### Training Data Consumer (TDC)  
1. Install CLI tools
2. Initialize contract service connection
3. Create DID via GitHub Pages
4. Retrieve contract using sequence number from TDP
5. Add signature to the contract
6. Register fully-signed contract

### Configuration
All environment variables can be configured through the UI:
- GitHub usernames for TDP and TDC
- Azure storage account and KeyVault settings
- Contract service URL
- CCRP (CCR Provider) username

### GitHub Integration
- DID creation automatically uploads to GitHub Pages
- Logout button for switching between GitHub accounts
- Verification links to check DID publication

## Prerequisites

- Python 3.8+
- GitHub CLI (`gh`) - for DID creation
- `envsubst` (from gettext) - for template processing
- `jq` - for JSON processing

The launch script will attempt to install missing dependencies.

## Architecture

```
demo-ui/
├── app.py              # Flask backend with API endpoints
├── templates/
│   └── index.html      # Single-page application UI
├── requirements.txt    # Python dependencies
└── README.md          # This file
```

## Demo Flow

### Role-Playing Demo

For a full demonstration of multi-party contract signing:

1. **Start as TDP:**
   - Select a scenario (e.g., BraTS)
   - Select "TDP" role
   - Run all setup steps
   - Create DID (authenticate as TDP GitHub account)
   - Sign and register the contract
   - Note the **sequence number** displayed

2. **Switch to TDC:**
   - Click "Logout GitHub". This may still result in conflicts, so it's recommended to use a separate Codespace instance under the TDC GitHub account.
   - Select "TDC" role
   - Enter the sequence number from TDP
   - Create DID (authenticate as TDC GitHub account)
   - Retrieve the contract
   - Sign and register the fully-signed contract

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Main UI page |
| `/api/scenarios` | GET | List available scenarios |
| `/api/setup/contract-template` | POST | Setup contract from template |
| `/api/step/install-cli` | POST | Install pyscitt CLI |
| `/api/step/contract-setup` | POST | Initialize contract service |
| `/api/step/create-did-tdp` | POST | Create DID for TDP |
| `/api/step/create-did-tdc` | POST | Create DID for TDC |
| `/api/step/verify-did` | POST | Verify DID publication |
| `/api/step/sign-contract-tdp` | POST | Sign contract as TDP |
| `/api/step/sign-contract-tdc` | POST | Sign contract as TDC |
| `/api/step/register-contract-tdp` | POST | Register TDP-signed contract |
| `/api/step/register-contract-tdc` | POST | Register fully-signed contract |
| `/api/step/retrieve-contract` | POST | Retrieve contract by seq number |
| `/api/step/view-receipt` | POST | View registration receipt |
| `/api/step/validate` | POST | Validate signed contract |
| `/api/github/logout` | POST | Logout from GitHub CLI |
| `/api/github/status` | GET | Check GitHub auth status |
| `/api/contract/view` | GET | View current contract.json |

## Troubleshooting

### "DID not found" error
- Wait a few seconds after DID creation for GitHub Pages to deploy
- Verify the DID URL is accessible in a browser
- Check that the GitHub repository exists with the correct name

### GitHub authentication issues
- Run `gh auth logout` in terminal
- Sign out in your IDE
- Re-authenticate with the correct account

### Script execution errors
- Ensure the main project venv is set up: `./demo/contract/0-install-cli.sh`
- Check that all prerequisites are installed

