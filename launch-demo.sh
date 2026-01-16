#!/bin/bash
# DEPA Training - Contract Signing Demo Launcher
# This script sets up and launches the user-friendly web UI for contract signing demos.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_UI_DIR="$SCRIPT_DIR/demo-ui"

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║     🔐  DEPA Training - Contract Signing Demo                   ║"
echo "║         Multi-Party Electronic Contract Signing                  ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is required but not installed.${NC}"
    exit 1
fi

echo -e "${YELLOW}📦 Setting up virtual environment...${NC}"

# Create virtual environment if it doesn't exist
if [ ! -d "$DEMO_UI_DIR/venv" ]; then
    python3 -m venv "$DEMO_UI_DIR/venv"
    echo -e "${GREEN}   ✓ Virtual environment created${NC}"
else
    echo -e "${GREEN}   ✓ Virtual environment already exists${NC}"
fi

# Activate virtual environment
source "$DEMO_UI_DIR/venv/bin/activate"

# Install dependencies
echo -e "${YELLOW}📥 Installing dependencies...${NC}"
pip install --quiet --disable-pip-version-check -r "$DEMO_UI_DIR/requirements.txt"
echo -e "${GREEN}   ✓ Dependencies installed${NC}"

# Check if envsubst is available
if ! command -v envsubst &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: envsubst not found. Installing gettext...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq gettext
    elif command -v yum &> /dev/null; then
        sudo yum install -y gettext
    else
        echo -e "${RED}Please install gettext manually for envsubst support.${NC}"
    fi
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: jq not found. Installing...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    else
        echo -e "${RED}Please install jq manually for JSON processing.${NC}"
    fi
fi

# Check GitHub CLI
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: GitHub CLI (gh) not found.${NC}"
    echo -e "   DID creation requires GitHub CLI. Install it from: https://cli.github.com/"
fi

echo ""
echo -e "${GREEN}${BOLD}🚀 Starting Demo UI Server...${NC}"
echo ""
echo -e "   ${CYAN}Open your browser and navigate to:${NC}"
echo ""
echo -e "   ${BOLD}   http://localhost:5050${NC}"
echo ""
echo -e "   ${YELLOW}Press Ctrl+C to stop the server${NC}"
echo ""
echo "────────────────────────────────────────────────────────────────────"
echo ""

# Start the Flask app
cd "$SCRIPT_DIR"
python3 "$DEMO_UI_DIR/app.py"

