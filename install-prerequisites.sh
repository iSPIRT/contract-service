#!/bin/bash

set -e

echo "=== Checking and installing prerequisites ==="

# Check if apt is installed
if ! command -v apt >/dev/null 2>&1; then
    echo "apt is not installed. Installing it using apt-get."
    sudo apt-get update
    sudo apt-get install -y apt
fi

# Arrays to track results
pkg_names=()
pkg_status=()
pkg_version=()

# Record result
record_result() {
    pkg_names+=("$1")
    pkg_status+=("$2")
    pkg_version+=("$3")
}

# Check & install function
check_and_install() {
    local cmd="$1"
    local pkg="$2"
    local install_cmd="$3"
    local ver_cmd="$4"

    if command -v "$cmd" >/dev/null 2>&1; then
        local ver
        ver=$($ver_cmd 2>/dev/null | head -n 1)
        echo "[OK] $pkg is already installed: $ver"
        record_result "$pkg" "Already Installed" "$ver"
    else
        echo "[Installing] $pkg..."
        eval "$install_cmd"
        local ver
        ver=$($ver_cmd 2>/dev/null | head -n 1)
        record_result "$pkg" "Installed Now" "$ver"
    fi
}

# --- Python3 ---
check_and_install python3 python3 "sudo apt install -y python3" "python3 --version"

# --- pip ---
check_and_install pip pip "sudo apt install -y python3-pip" "pip --version"

# --- python3-venv ---
# Get Python version (e.g., "3.12" from "Python 3.12.3")
PYTHON_VER=$(python3 --version | awk '{print $2}' | cut -d. -f1,2)
PYTHON_VER_PKG="python${PYTHON_VER}-venv"

# Check if version-specific venv package is installed and ensurepip works
if dpkg -l | grep -q "^ii.*${PYTHON_VER_PKG}" && python3 -m ensurepip --version >/dev/null 2>&1; then
    ver=$(python3 --version | awk '{print $2}' || echo "installed")
    echo "[OK] python3-venv is already installed: Python $ver venv module (with ensurepip)"
    record_result "python3-venv" "Already Installed" "Python $ver venv module"
else
    echo "[Installing] python3-venv (version-specific package for ensurepip support)..."
    # Install version-specific venv package (e.g., python3.12-venv)
    # This ensures ensurepip is available for venv creation
    sudo apt install -y "$PYTHON_VER_PKG" || sudo apt install -y python3-venv
    ver=$(python3 --version | awk '{print $2}' || echo "installed")
    record_result "python3-venv" "Installed Now" "Python $ver venv module"
fi

# --- jq ---
check_and_install jq jq "sudo apt install -y jq" "jq --version"

# --- GitHub CLI (gh) ---
if command -v gh >/dev/null 2>&1; then
    ver=$(gh --version | head -n 1)
    echo "[OK] GitHub CLI (gh) is already installed: $ver"
    record_result "GitHub CLI (gh)" "Already Installed" "$ver"
else
    echo "[Installing] GitHub CLI (gh)..."
    # Try installing from default repositories first
    if ! sudo apt install -y gh 2>/dev/null; then
        # If apt package not available, use official installation method
        echo "[Installing] Adding GitHub CLI official repository..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update -qq
        sudo apt install -y gh
    fi
    ver=$(gh --version 2>/dev/null | head -n 1 || echo "installed")
    record_result "GitHub CLI (gh)" "Installed Now" "$ver"
fi

# --- Docker ---
if command -v docker >/dev/null 2>&1; then
    ver=$(docker -v)
    echo "[OK] docker is already installed: $ver"
    record_result "docker" "Already Installed" "$ver"
else
    echo "[Installing] docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    ver=$(docker -v)
    record_result "docker" "Installed Now" "$ver"
fi

# --- Docker group setup ---
if groups "$USER" | grep &>/dev/null '\bdocker\b'; then
    echo "[OK] User '$USER' is already in docker group."
else
    echo "[Adding] User '$USER' to docker group..."
    sudo usermod -aG docker "$USER"
    echo "You may need to log out and log back in for docker group changes to take effect."
    sudo rm get-docker.sh
fi

# --- Docker DNS configuration ---
echo "[Configuring] Docker DNS settings..."
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
DOCKER_DNS_NEEDED=false

# Get system DNS resolvers from /etc/resolv.conf, fallback to Google DNS
SYSTEM_DNS=$(grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -2 | tr '\n' ' ' || echo "")
if [ -z "$SYSTEM_DNS" ]; then
    SYSTEM_DNS="8.8.8.8 8.8.4.4"
fi

# Convert space-separated DNS to JSON array format
DNS_ARRAY=$(echo "$SYSTEM_DNS" | awk '{printf "[\""; for(i=1;i<=NF;i++){printf "%s", $i; if(i<NF) printf "\", \""} printf "\"]"}')

if [ -f "$DOCKER_DAEMON_JSON" ]; then
    # Check if DNS is already configured
    if ! grep -q "\"dns\"" "$DOCKER_DAEMON_JSON" 2>/dev/null; then
        DOCKER_DNS_NEEDED=true
    fi
else
    DOCKER_DNS_NEEDED=true
fi

if [ "$DOCKER_DNS_NEEDED" = true ]; then
    echo "[Configuring] Adding DNS settings to Docker daemon..."
    sudo mkdir -p /etc/docker
    
    if [ -f "$DOCKER_DAEMON_JSON" ]; then
        # Backup existing config and merge DNS settings
        sudo cp "$DOCKER_DAEMON_JSON" "${DOCKER_DAEMON_JSON}.bak"
        # Use jq if available to merge DNS settings
        if command -v jq >/dev/null 2>&1; then
            # Build DNS array from space-separated list
            DNS_JSON_ARRAY="["
            FIRST=true
            for dns in $SYSTEM_DNS; do
                if [ "$FIRST" = true ]; then
                    DNS_JSON_ARRAY="${DNS_JSON_ARRAY}\"$dns\""
                    FIRST=false
                else
                    DNS_JSON_ARRAY="${DNS_JSON_ARRAY}, \"$dns\""
                fi
            done
            DNS_JSON_ARRAY="${DNS_JSON_ARRAY}]"
            
            # Merge DNS into existing config
            sudo cat "$DOCKER_DAEMON_JSON" | jq ". + {dns: $DNS_JSON_ARRAY}" | sudo tee "${DOCKER_DAEMON_JSON}.tmp" > /dev/null
            sudo mv "${DOCKER_DAEMON_JSON}.tmp" "$DOCKER_DAEMON_JSON"
        else
            # Fallback: create new config with DNS (overwrites existing)
            echo "{\"dns\": $DNS_ARRAY}" | sudo tee "$DOCKER_DAEMON_JSON" > /dev/null
        fi
    else
        # Create new daemon.json with DNS settings
        echo "{\"dns\": $DNS_ARRAY}" | sudo tee "$DOCKER_DAEMON_JSON" > /dev/null
    fi
    
    # Restart Docker daemon to apply changes
    echo "[Restarting] Docker daemon to apply DNS configuration..."
    sudo systemctl restart docker || sudo service docker restart || true
    echo "[OK] Docker DNS configured with: $SYSTEM_DNS"
else
    echo "[OK] Docker DNS is already configured."
fi

# --- Summary Table ---
echo
echo "=== Installation Summary ==="
printf "%-30s | %-17s | %-30s\n" "Package" "Status" "Version"
printf "%-30s | %-17s | %-30s\n" "------------------------------" "-----------------" "------------------------------"

for i in "${!pkg_names[@]}"; do
    printf "%-30s | %-17s | %-30s\n" "${pkg_names[$i]}" "${pkg_status[$i]}" "${pkg_version[$i]}"
done

echo "=== All prerequisites are installed. ==="