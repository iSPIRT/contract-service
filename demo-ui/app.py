#!/usr/bin/env python3
"""
DEPA Training Contract Signing Demo UI
A user-friendly web interface for multi-party electronic contract signing.
"""

import os
import subprocess
import json
import threading
import queue
import uuid
import re
from datetime import datetime
from pathlib import Path
from flask import Flask, render_template, request, jsonify, Response
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Project root directory
PROJECT_ROOT = Path(__file__).parent.parent.absolute()

# Store session state
sessions = {}

# Scenario configurations
SCENARIOS = {
    "brats": {
        "name": "BraTS (Brain Tumor Segmentation)",
        "description": "Medical imaging scenario with 4 data providers sharing brain MRI scans for tumor segmentation model training.",
        "template": "brats-contract-template.json",
        "icon": "🧠",
        "variables": {
            "AZURE_BRATS_A_CONTAINER_NAME": "bratsacontainer",
            "AZURE_BRATS_B_CONTAINER_NAME": "bratsbcontainer",
            "AZURE_BRATS_C_CONTAINER_NAME": "bratsccontainer",
            "AZURE_BRATS_D_CONTAINER_NAME": "bratsdcontainer"
        }
    },
    "covid": {
        "name": "COVID-19",
        "description": "Population-scale disease surveillance scenario combining ICMR, CoWIN and hospitalization data for COVID-19 pandemic response analytics.",
        "template": "covid-contract-template.json",
        "icon": "🦠",
        "variables": {
            "AZURE_ICMR_CONTAINER_NAME": "icmrcontainer",
            "AZURE_COWIN_CONTAINER_NAME": "cowincontainer",
            "AZURE_INDEX_CONTAINER_NAME": "indexcontainer"
        }
    },
    "credit-risk": {
        "name": "Credit Risk Assessment",
        "description": "Financial services scenario with multiple banks and bureaus collaborating on credit risk models.",
        "template": "credit-risk-contract-template.json",
        "icon": "💳",
        "variables": {
            "AZURE_BANK_A_CONTAINER_NAME": "bankacontainer",
            "AZURE_BANK_B_CONTAINER_NAME": "bankbcontainer",
            "AZURE_BUREAU_CONTAINER_NAME": "bureaucontainer",
            "AZURE_FINTECH_CONTAINER_NAME": "fintechcontainer"
        }
    }
}

# Default configuration
DEFAULT_CONFIG = {
    "TDP_USERNAME": "<tdp-username>",
    "TDC_USERNAME": "<tdc-username>",
    "CCRP_USERNAME": "<ccrp-username>",
    "AZURE_STORAGE_ACCOUNT_NAME": "<storage-account-name>",
    "AZURE_KEYVAULT_ENDPOINT": "<akv>.vault.azure.net",
    "CONTRACT_SERVICE_URL": "https://<contract-service-url>:<port>"
}


def run_command(cmd, env=None, cwd=None, shell=True):
    """Execute a shell command and return output."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    
    # Use bash explicitly to support 'source' command
    if shell and 'source' in cmd:
        cmd = f'bash -c "{cmd}"'
    
    try:
        result = subprocess.run(
            cmd,
            shell=shell,
            cwd=cwd or PROJECT_ROOT,
            env=full_env,
            capture_output=True,
            text=True,
            timeout=120,
            executable='/bin/bash' if shell else None
        )
        return {
            "success": result.returncode == 0,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "returncode": result.returncode
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "stdout": "", "stderr": "Command timed out", "returncode": -1}
    except Exception as e:
        return {"success": False, "stdout": "", "stderr": str(e), "returncode": -1}


def stream_command(cmd, env=None, cwd=None):
    """Execute a command and yield output line by line."""
    full_env = os.environ.copy()
    if env:
        full_env.update(env)
    
    process = subprocess.Popen(
        cmd,
        shell=True,
        cwd=cwd or PROJECT_ROOT,
        env=full_env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )
    
    for line in iter(process.stdout.readline, ''):
        yield line
    
    process.wait()
    return process.returncode


@app.route('/')
def index():
    """Render the main UI page."""
    return render_template('index.html', scenarios=SCENARIOS, default_config=DEFAULT_CONFIG)


@app.route('/api/scenarios')
def get_scenarios():
    """Get available scenarios."""
    return jsonify(SCENARIOS)


@app.route('/api/template/<scenario>')
def get_template(scenario):
    """Get the contract template for a scenario."""
    if scenario not in SCENARIOS:
        return jsonify({"error": "Invalid scenario"}), 400
    
    template_file = PROJECT_ROOT / "quick-demos" / SCENARIOS[scenario]["template"]
    
    if not template_file.exists():
        return jsonify({"error": "Template file not found"}), 404
    
    try:
        with open(template_file) as f:
            template = json.load(f)
        return jsonify({"template": template, "scenario": scenario})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route('/api/session', methods=['POST'])
def create_session():
    """Create a new demo session."""
    session_id = str(uuid.uuid4())[:8]
    sessions[session_id] = {
        "created": datetime.now().isoformat(),
        "config": {},
        "scenario": None,
        "role": None,
        "contract_seq_no": None,
        "steps_completed": [],
        "did_created": {"tdp": False, "tdc": False}
    }
    return jsonify({"session_id": session_id})


@app.route('/api/session/<session_id>/config', methods=['POST'])
def update_config(session_id):
    """Update session configuration."""
    if session_id not in sessions:
        return jsonify({"error": "Session not found"}), 404
    
    data = request.json
    sessions[session_id]["config"].update(data.get("config", {}))
    sessions[session_id]["scenario"] = data.get("scenario")
    sessions[session_id]["role"] = data.get("role")
    
    return jsonify({"success": True})


@app.route('/api/setup/contract-template', methods=['POST'])
def setup_contract_template():
    """Copy and set up the contract template for a scenario."""
    data = request.json
    scenario = data.get("scenario")
    config = data.get("config", DEFAULT_CONFIG)
    
    if scenario not in SCENARIOS:
        return jsonify({"error": "Invalid scenario"}), 400
    
    scenario_config = SCENARIOS[scenario]
    env = {**config, **scenario_config["variables"]}
    
    # Copy template
    template_src = PROJECT_ROOT / "quick-demos" / scenario_config["template"]
    template_dst = PROJECT_ROOT / "demo" / "contract" / "contract_template.json"
    
    try:
        import shutil
        shutil.copy(template_src, template_dst)
    except Exception as e:
        return jsonify({"error": f"Failed to copy template: {e}"}), 500
    
    # Run envsubst
    cmd = f"envsubst < demo/contract/contract_template.json > demo/contract/contract.json"
    result = run_command(cmd, env=env)
    
    if not result["success"]:
        return jsonify({"error": "Failed to substitute variables", "details": result["stderr"]}), 500
    
    # Run update-contract.sh
    cmd = "./demo/contract/update-contract.sh"
    result = run_command(cmd, env=env)
    
    # Read the generated contract
    contract_file = PROJECT_ROOT / "demo" / "contract" / "contract.json"
    contract_content = None
    if contract_file.exists():
        with open(contract_file) as f:
            contract_content = json.load(f)
    
    return jsonify({
        "success": result["success"],
        "output": result["stdout"] + result["stderr"],
        "contract": contract_content
    })


@app.route('/api/step/install-cli', methods=['POST'])
def install_cli():
    """Run 0-install-cli.sh."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "./demo/contract/0-install-cli.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


@app.route('/api/step/contract-setup', methods=['POST'])
def contract_setup():
    """Run 1-contract-setup.sh."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/1-contract-setup.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


def format_output(result):
    """Format command output with stdout first, then stderr."""
    output = result["stdout"].strip() if result["stdout"] else ""
    if result["stderr"]:
        stderr = result["stderr"].strip()
        if output:
            output += "\n\n--- Debug/Trace Output ---\n" + stderr
        else:
            output = stderr
    return output


@app.route('/api/step/create-did-tdp', methods=['POST'])
def create_did_tdp():
    """Run 2-create-did.sh for TDP."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/2-create-did.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result),
        "did_url": f"https://{config.get('TDP_USERNAME', 'unknown')}.github.io/.well-known/did.json"
    })


@app.route('/api/step/verify-did', methods=['POST'])
def verify_did():
    """Verify DID is published on GitHub Pages."""
    data = request.json
    username = data.get("username")
    
    if not username:
        return jsonify({"error": "Username required"}), 400
    
    cmd = f"curl -s https://{username}.github.io/.well-known/did.json"
    result = run_command(cmd)
    
    try:
        did_doc = json.loads(result["stdout"])
        return jsonify({"success": True, "did_document": did_doc})
    except json.JSONDecodeError:
        return jsonify({"success": False, "error": "DID not found or invalid", "raw": result["stdout"]})


@app.route('/api/step/sign-contract-tdp', methods=['POST'])
def sign_contract_tdp():
    """Run 3-sign-contract.sh for TDP."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/3-sign-contract.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


@app.route('/api/step/register-contract-tdp', methods=['POST'])
def register_contract_tdp():
    """Run 4-register-contract.sh for TDP."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/4-register-contract.sh"
    result = run_command(cmd, env=config)
    
    # Format output
    output = format_output(result)
    
    # Extract sequence number from output
    seq_no = None
    
    # Try specific patterns first (order matters - most specific first)
    patterns = [
        r'\.(\d+)\.cose',                             # "2.26.cose" -> extract 26 (PRIORITY)
        r'[Ss]equence\s*(?:number|no)?[:\s]+(\d+)',  # "Sequence number: 26" or "sequence: 26"
        r'[Ee]ntry[:\s]+(\d+)',                       # "Entry: 26" or "Entry 26"
        r'seqno[:\s]+(\d+)',                          # "seqno: 26"
        r'submitted.*?(\d+)',                         # "submitted ... 26"
        r'\b(\d{2,})\b'                               # Any 2+ digit number (fallback - last resort)
    ]
    
    for pattern in patterns:
        match = re.search(pattern, output, re.IGNORECASE)
        if match:
            candidate = int(match.group(1))
            # Skip single digits and version-like numbers (2, 3, etc.)
            if pattern == r'\b(\d{2,})\b' or candidate >= 10:
                seq_no = candidate
                break
    
    return jsonify({
        "success": result["success"],
        "output": output,
        "sequence_number": seq_no
    })


@app.route('/api/step/view-receipt', methods=['POST'])
def view_receipt():
    """Run 5-view-receipt.sh."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/5-view-receipt.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


@app.route('/api/step/validate', methods=['POST'])
def validate():
    """Run 6-validate.sh."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/6-validate.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


@app.route('/api/step/create-did-tdc', methods=['POST'])
def create_did_tdc():
    """Run 7-create-did.sh for TDC."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/7-create-did.sh"
    result = run_command(cmd, env=config)
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result),
        "did_url": f"https://{config.get('TDC_USERNAME', 'unknown')}.github.io/.well-known/did.json"
    })


@app.route('/api/step/retrieve-contract', methods=['POST'])
def retrieve_contract():
    """Run 8-retrieve-contract.sh."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    seq_no = data.get("sequence_number")
    
    if not seq_no:
        return jsonify({"error": "Sequence number required"}), 400
    
    cmd = f"source venv/bin/activate && ./demo/contract/8-retrieve-contract.sh {seq_no}"
    result = run_command(cmd, env=config)
    
    # Check if contract was successfully retrieved (scripts use /tmp/contracts, not project tmp)
    if result["success"]:
        contract_file = Path(f"/tmp/contracts/2.{seq_no}.cose")
        if not contract_file.exists():
            return jsonify({
                "success": False,
                "output": format_output(result) + f"\n\nWarning: Expected contract file {contract_file} was not found after retrieval."
            })
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


@app.route('/api/step/sign-contract-tdc', methods=['POST'])
def sign_contract_tdc():
    """Run 9-sign-contract.sh for TDC."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    seq_no = data.get("sequence_number")
    
    if not seq_no:
        return jsonify({"error": "Sequence number required"}), 400
    
    # Check if the contract file exists before trying to sign (scripts use /tmp/contracts)
    contract_file = Path(f"/tmp/contracts/2.{seq_no}.cose")
    if not contract_file.exists():
        return jsonify({
            "success": False,
            "error": f"Contract file not found: {contract_file}\n\nPlease ensure you've retrieved the contract first (step 5.5).",
            "output": f"Error: Contract file 2.{seq_no}.cose not found in /tmp/contracts/\n\nMake sure you:\n1. Retrieved the contract with sequence number {seq_no}\n2. The retrieve step completed successfully"
        }), 400
    
    # Check if TDC DID exists
    tdc_username = config.get("TDC_USERNAME", "")
    did_file = Path(f"/tmp/{tdc_username}/did.json")
    if not did_file.exists():
        return jsonify({
            "success": False,
            "error": f"TDC DID not found: {did_file}\n\nPlease create the TDC DID first (step 4).",
            "output": f"Error: DID file not found at {did_file}\n\nMake sure you've created the DID for TDC in step 4."
        }), 400
    
    cmd = f"source venv/bin/activate && ./demo/contract/9-sign-contract.sh {seq_no}"
    result = run_command(cmd, env=config)
    
    if not result["success"]:
        # Provide helpful error message
        error_msg = format_output(result)
        if "No such file or directory" in error_msg:
            error_msg += f"\n\nTip: Make sure the contract file /tmp/contracts/2.{seq_no}.cose exists."
        elif "did.json" in error_msg:
            error_msg += f"\n\nTip: Make sure you've created the DID for {tdc_username}."
    
    return jsonify({
        "success": result["success"],
        "output": format_output(result)
    })


@app.route('/api/step/register-contract-tdc', methods=['POST'])
def register_contract_tdc():
    """Run 10-register-contract.sh for TDC."""
    data = request.json
    config = data.get("config", DEFAULT_CONFIG)
    
    cmd = "source venv/bin/activate && ./demo/contract/10-register-contract.sh"
    result = run_command(cmd, env=config)
    
    # Format output
    output = format_output(result)
    
    # Extract sequence number from output (same logic as TDP)
    seq_no = None
    
    # Try specific patterns first (order matters - most specific first)
    patterns = [
        r'\.(\d+)\.cose',                             # "2.26.cose" -> extract 26 (PRIORITY)
        r'[Ss]equence\s*(?:number|no)?[:\s]+(\d+)',  # "Sequence number: 26" or "sequence: 26"
        r'[Ee]ntry[:\s]+(\d+)',                       # "Entry: 26" or "Entry 26"
        r'seqno[:\s]+(\d+)',                          # "seqno: 26"
        r'submitted.*?(\d+)',                         # "submitted ... 26"
        r'\b(\d{2,})\b'                               # Any 2+ digit number (fallback - last resort)
    ]
    
    for pattern in patterns:
        match = re.search(pattern, output, re.IGNORECASE)
        if match:
            candidate = int(match.group(1))
            # Skip single digits and version-like numbers (2, 3, etc.)
            if pattern == r'\b(\d{2,})\b' or candidate >= 10:
                seq_no = candidate
                break
    
    return jsonify({
        "success": result["success"],
        "output": output,
        "sequence_number": seq_no
    })


@app.route('/api/github/logout', methods=['POST'])
def github_logout():
    """Logout from GitHub CLI."""
    # First try to logout with yes piped in for confirmation
    cmd = "echo 'Y' | gh auth logout --hostname github.com 2>&1 || true"
    result = run_command(cmd)
    
    return jsonify({
        "success": True,
        "output": "Logged out from GitHub CLI successfully."
    })


@app.route('/api/github/status', methods=['GET'])
def github_status():
    """Check GitHub auth status and return username if logged in."""
    cmd = "gh auth status 2>&1"
    result = run_command(cmd)
    
    output = result["stdout"] + result["stderr"]
    logged_in = "Logged in to" in output
    
    # Extract username from output like "Logged in to github.com account username (keyring)"
    username = None
    if logged_in:
        match = re.search(r'account\s+(\S+)', output)
        if match:
            username = match.group(1).strip('()')
    
    return jsonify({
        "logged_in": logged_in,
        "username": username,
        "output": output
    })


@app.route('/api/github/login-device', methods=['POST'])
def github_login_device():
    """Initiate GitHub device flow login."""
    # Need --web for non-interactive mode, but we'll kill the process fast
    # before it opens the browser. Frontend will open it in a new tab.
    cmd = "gh auth login --hostname github.com --web 2>&1"
    
    try:
        # Set BROWSER env var to a no-op to prevent gh from opening browser
        env = os.environ.copy()
        env['BROWSER'] = '/bin/true'  # No-op command that always succeeds
        
        process = subprocess.Popen(
            cmd,
            shell=True,
            cwd=PROJECT_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.PIPE,
            text=True,
            executable='/bin/bash',
            env=env
        )
        
        # Read output until we get the device code
        output_lines = []
        device_code = None
        auth_url = None
        
        import time
        
        # Read initial output to get device code (with timeout)
        start_time = time.time()
        
        while time.time() - start_time < 2:  # Wait max 2 seconds for device code
            # Use select to check if output is available
            import select
            ready, _, _ = select.select([process.stdout], [], [], 0.05)
            
            if ready:
                line = process.stdout.readline()
                if not line:
                    break
                output_lines.append(line)
                
                # Look for the one-time code
                if "one-time code" in line.lower() or "code:" in line.lower():
                    match = re.search(r'([A-Z0-9]{4}-[A-Z0-9]{4})', line)
                    if match and not device_code:
                        device_code = match.group(1)
                        # Got the code! Kill the process immediately to prevent browser opening
                        try:
                            process.kill()  # Use kill() not terminate() for immediate stop
                            process.wait(timeout=0.5)
                        except:
                            pass
                        break
        
        # Clean up the process if still running
        if process.poll() is None:
            try:
                process.kill()  # Force kill
                process.wait(timeout=0.5)
            except:
                pass
        
        output = ''.join(output_lines)
        
        # If we have a device code, return it for the UI
        if device_code:
            return jsonify({
                "success": False,
                "waiting_for_auth": True,
                "device_code": device_code,
                "auth_url": "https://github.com/login/device",
                "output": output,
                "message": f"Please visit https://github.com/login/device and enter code: {device_code}"
            })
        
        # No device code found
        return jsonify({
            "success": False,
            "error": "Could not retrieve device code",
            "output": output
        })
        
    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        })


@app.route('/api/github/login-token', methods=['POST'])
def github_login_token():
    """Login to GitHub using a Personal Access Token."""
    data = request.json
    token = data.get("token", "").strip()
    
    if not token:
        return jsonify({"success": False, "error": "Token is required"}), 400
    
    # Validate token format (basic check)
    if not (token.startswith("ghp_") or token.startswith("github_pat_") or len(token) >= 40):
        return jsonify({
            "success": False, 
            "error": "Invalid token format. Token should start with 'ghp_' or 'github_pat_'"
        }), 400
    
    # Login with token
    cmd = f"echo '{token}' | gh auth login --with-token 2>&1"
    result = run_command(cmd)
    
    output = result["stdout"] + result["stderr"]
    
    # Check if login succeeded by checking status
    status_cmd = "gh auth status 2>&1"
    status_result = run_command(status_cmd)
    status_output = status_result["stdout"] + status_result["stderr"]
    
    success = "Logged in to" in status_output
    
    # Extract username
    username = None
    if success:
        match = re.search(r'account\s+(\S+)', status_output)
        if match:
            username = match.group(1).strip('()')
    
    return jsonify({
        "success": success,
        "username": username,
        "output": output if not success else f"Successfully logged in as {username}"
    })


@app.route('/api/contract/view', methods=['GET'])
def view_contract():
    """View the current contract.json."""
    contract_file = PROJECT_ROOT / "demo" / "contract" / "contract.json"
    
    if not contract_file.exists():
        return jsonify({"error": "No contract found. Please set up a scenario first."}), 404
    
    with open(contract_file) as f:
        contract = json.load(f)
    
    return jsonify({"contract": contract})


@app.route('/api/shutdown', methods=['POST'])
def shutdown():
    """Gracefully shutdown the Flask server."""
    import signal
    
    def shutdown_server():
        """Kill the Flask process and all its children."""
        import time
        time.sleep(0.5)  # Give time for response to be sent
        os.kill(os.getpid(), signal.SIGTERM)
    
    # Start shutdown in a background thread
    shutdown_thread = threading.Thread(target=shutdown_server)
    shutdown_thread.daemon = True
    shutdown_thread.start()
    
    return jsonify({"success": True, "message": "Server shutting down..."})


if __name__ == '__main__':
    print("""
    ╔══════════════════════════════════════════════════════════════╗
    ║     DEPA Training - Contract Signing Demo UI                ║
    ║     Open http://localhost:5050 in your browser              ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
    app.run(host='0.0.0.0', port=5050, debug=True)

