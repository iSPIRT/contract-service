#!/bin/bash

set -e

echo "=== Checking and installing prerequisites ==="

# Update package lists
sudo apt update -qq

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
PYTHON_VER=$(python3 --version | awk '{print $2}' | cut -d. -f1,2)
PYTHON_VER_PKG="python${PYTHON_VER}-venv"

if dpkg -l | grep -q "^ii.*${PYTHON_VER_PKG}" && python3 -m ensurepip --version >/dev/null 2>&1; then
    ver=$(python3 --version | awk '{print $2}' || echo "installed")
    echo "[OK] python3-venv is already installed: Python $ver venv module (with ensurepip)"
    record_result "python3-venv" "Already Installed" "Python $ver venv module"
else
    echo "[Installing] python3-venv..."
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
    if ! sudo apt install -y gh 2>/dev/null; then
        echo "[Installing] Adding GitHub CLI official repository..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
            sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
            sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
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
    rm -f get-docker.sh
fi

# --- Docker group setup ---
if ! getent group docker >/dev/null 2>&1; then
    echo "[Creating] docker group..."
    sudo groupadd docker
fi

# Get current user (handle cases where USER is not set)
CURRENT_USER=${USER:-$(whoami 2>/dev/null || echo "root")}

if [ "$CURRENT_USER" = "root" ]; then
    echo "[OK] Running as root - no need to add to docker group."
elif id "$CURRENT_USER" >/dev/null 2>&1 && groups "$CURRENT_USER" 2>/dev/null | grep -q '\bdocker\b'; then
    echo "[OK] User '$CURRENT_USER' is already in docker group."
elif id "$CURRENT_USER" >/dev/null 2>&1; then
    echo "[Adding] User '$CURRENT_USER' to docker group..."
    sudo usermod -aG docker "$CURRENT_USER"
    echo "[Info] You may need to log out and log back in for docker group changes to take effect."
else
    echo "[Info] Could not determine current user - skipping docker group setup."
fi

# --- Docker DNS configuration ---
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

# Get system DNS resolvers, fallback to Google DNS
SYSTEM_DNS=$(grep -E "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -2 | tr '\n' ' ' || echo "")
[ -z "$SYSTEM_DNS" ] && SYSTEM_DNS="8.8.8.8 8.8.4.4"

# Check if DNS configuration is needed
DNS_NEEDED=false
if [ ! -f "$DOCKER_DAEMON_JSON" ] || ! grep -q '"dns"' "$DOCKER_DAEMON_JSON" 2>/dev/null; then
    DNS_NEEDED=true
fi

if [ "$DNS_NEEDED" = true ]; then
    echo "[Configuring] Docker DNS settings..."
    sudo mkdir -p /etc/docker
    
    # Build DNS JSON array using jq if available, otherwise simple string replacement
    if command -v jq >/dev/null 2>&1 && [ -f "$DOCKER_DAEMON_JSON" ]; then
        # Merge DNS into existing config
        sudo cp "$DOCKER_DAEMON_JSON" "${DOCKER_DAEMON_JSON}.bak"
        DNS_LIST=$(echo "$SYSTEM_DNS" | tr ' ' '\n' | jq -R . | jq -s .)
        sudo cat "$DOCKER_DAEMON_JSON" | jq ". + {dns: $DNS_LIST}" | sudo tee "${DOCKER_DAEMON_JSON}.tmp" > /dev/null
        sudo mv "${DOCKER_DAEMON_JSON}.tmp" "$DOCKER_DAEMON_JSON"
    else
        # Create new config with DNS
        DNS_ARRAY=$(echo "$SYSTEM_DNS" | awk '{printf "[\""; for(i=1;i<=NF;i++){printf "%s", $i; if(i<NF) printf "\", \""} printf "\"]"}')
        echo "{\"dns\": $DNS_ARRAY}" | sudo tee "$DOCKER_DAEMON_JSON" > /dev/null
    fi
    
    # Try to restart Docker (suppress errors)
    echo "[Restarting] Docker daemon..."
    if systemctl list-units --type=service --all 2>/dev/null | grep -qE '\bdocker\.service\b'; then
        sudo systemctl restart docker 2>/dev/null && echo "[OK] Docker daemon restarted" || \
            echo "[Info] Docker service found but restart failed - configuration saved"
    elif command -v service >/dev/null 2>&1; then
        sudo service docker restart 2>/dev/null && echo "[OK] Docker daemon restarted" || \
            echo "[Info] Could not restart Docker - configuration saved"
    else
        echo "[Info] Docker service not found - configuration saved, restart manually when ready"
    fi
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
