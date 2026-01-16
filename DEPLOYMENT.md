# SCITT Contract Ledger - 24/7 Deployment Guide

This guide explains how to run the SCITT Contract Ledger service persistently (24/7) with the ability to stop, start, and restart it.

## Prerequisites

- Docker installed and running
- Python 3.8 or higher
- PLATFORM environment variable set (e.g., `export PLATFORM=virtual`)

## Initial Setup

First, build the Docker image:

```bash
export PLATFORM=<virtual|sgx>
./docker/build.sh
```

## Option 1: Simple Service Management (Recommended for Quick Setup)

### Initial Deployment

Run the service for the first time:

```bash
export PLATFORM=<virtual|sgx>
./docker/run-service.sh
```

This will:
- Start the service as a Docker container with auto-restart enabled
- The container will automatically restart if it crashes
- The container will persist even after terminal closes
- Display management commands when complete

### Managing the Service

Use the service manager script:

```bash
# Check service status
./docker/service-manager.sh status

# Stop the service
./docker/service-manager.sh stop

# Start the service
./docker/service-manager.sh start

# Restart the service
./docker/service-manager.sh restart

# View live logs
./docker/service-manager.sh logs

# Remove service completely
./docker/service-manager.sh remove
```

### Direct Docker Commands

You can also use Docker directly:

```bash
# View logs
docker logs -f scitt-service

# Stop service
docker stop scitt-service

# Start service
docker start scitt-service

# Restart service
docker restart scitt-service

# Check status
docker ps | grep scitt-service
```

### Auto-Start on System Boot

The container is created with `--restart unless-stopped` policy, which means:
- It will automatically restart if it crashes
- It will start when Docker daemon starts (after system reboot)
- It won't restart if you manually stop it

## Option 2: Systemd Service (Recommended for Production)

For a more robust production deployment with system-level integration:

### Install the Service

```bash
# Copy the service file to systemd
sudo cp docker/scitt-ledger.service /etc/systemd/system/

# Reload systemd to recognize the new service
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable scitt-ledger.service

# Start the service
sudo systemctl start scitt-ledger.service
```

### Managing the Systemd Service

```bash
# Check service status
sudo systemctl status scitt-ledger.service

# Stop the service
sudo systemctl stop scitt-ledger.service

# Start the service
sudo systemctl start scitt-ledger.service

# Restart the service
sudo systemctl restart scitt-ledger.service

# View logs
sudo journalctl -u scitt-ledger.service -f

# Disable auto-start on boot
sudo systemctl disable scitt-ledger.service
```

## Accessing the Service

Once running, the service is available at:
- **URL**: `https://localhost:8000`
- **Container Name**: `scitt-service`

You can customize the port by setting `CCF_PORT` before running:

```bash
export PLATFORM=<virtual|sgx>
export CCF_PORT=9000
./docker/run-service.sh
```

## Troubleshooting

### Check if service is running

```bash
docker ps | grep scitt-service
```

### View recent logs

```bash
docker logs --tail 100 scitt-service
```

### Service won't start

1. Check if port 8000 is already in use:
   ```bash
   netstat -tulpn | grep 8000
   ```

2. Check Docker logs for errors:
   ```bash
   docker logs scitt-service
   ```

3. Remove and recreate the service:
   ```bash
   ./docker/service-manager.sh remove
   export PLATFORM=<virtual|sgx>
   ./docker/build.sh
   ./docker/run-service.sh
   ```

### Container keeps restarting

Check the logs to identify the issue:
```bash
docker logs scitt-service
```

## Differences from Original run-dev.sh

The new `run-service.sh` differs from `run-dev.sh` in these key ways:

1. **No cleanup trap**: The container is not automatically removed when the script exits
2. **Restart policy**: Adds `--restart unless-stopped` to auto-restart on failures
3. **Fixed container name**: Uses `scitt-service` instead of timestamp-based names
4. **No log tailing**: Script exits after setup, leaving container running in background
5. **Persistent volume**: Volume is reused if it exists (`|| true` on volume create)

## ⚠️ IMPORTANT: CCF Restart Limitations

**Critical:** The CCF (Confidential Consortium Framework) ledger **cannot restart with existing data** using the current configuration. The service is configured with "Start" mode, which initializes a new network.

### What This Means:

| Action | Result |
|--------|--------|
| Container crashes | ✅ Auto-restarts with restart policy |
| Process crashes inside container | ✅ Container keeps running, CCF restarts |
| Manual `docker restart` | ❌ **FAILS** - ledger already exists |
| System reboot | ❌ **FAILS** - ledger already exists |
| Manual `docker start` (after stop) | ❌ **FAILS** - ledger already exists |

### The Problem:
When you **stop and restart** the container, it tries to run CCF's "Start" command again, which fails with:
```
Fatal: On start, ledger directory should not exist (ledger). Exiting.
```

### Solutions:

**For Development (Current Setup):**
- Service runs continuously and is stable
- **Restart Policy protects against crashes** (container auto-restarts)
- **DO NOT manually restart the container**
- If you need to restart, use: `./docker/service-manager.sh restart` (removes data and starts fresh)

**For Production (Future Enhancement):**
- Implement CCF "Recover" mode for restarts with persistent data
- Requires modification to dev-config.json to support recovery
- See CCF documentation for recovery configuration

## Restart Policies and Maintenance

### Docker Restart Policy (Option 1)

The `run-service.sh` uses `--restart unless-stopped`:

| Scenario | Behavior |
|----------|----------|
| Container **process crashes** | ✅ Automatically restarts (works fine) |
| Docker daemon restarts | ⚠️  Container starts but **CCF fails** (use fresh start) |
| System reboot | ⚠️  Container starts but **CCF fails** (use fresh start) |
| Manual stop (`docker stop`) | ✅ Stays stopped (for maintenance) |

### Systemd Restart Policy (Option 2)

Enhanced with maintenance-friendly settings:

| Setting | Purpose |
|---------|---------|
| `Restart=on-failure` | Restarts only on failures, not clean exits |
| `RestartSec=10s` | Waits 10 seconds before restart |
| `StartLimitBurst=5` | Max 5 restart attempts |
| `StartLimitInterval=200s` | Within 200 seconds window |
| `TimeoutStopSec=30s` | Graceful shutdown timeout |
| `After=network-online.target` | Waits for network before starting |

## Maintenance Helper Script

A dedicated maintenance script (`docker/maintenance.sh`) provides easy management:

```bash
# Enter maintenance mode (safe for backups/updates)
./docker/maintenance.sh start-maintenance

# Exit maintenance mode
./docker/maintenance.sh end-maintenance

# Create a backup
./docker/maintenance.sh backup

# Restore from backup
./docker/maintenance.sh restore backups/scitt-backup-20231203_120000.tar.gz

# Check service health
./docker/maintenance.sh health-check

# View restart statistics
./docker/maintenance.sh restart-stats
```

### Maintenance Window Best Practices

#### Before Maintenance (Graceful Shutdown)

```bash
# Option 1: Docker
docker stop scitt-service  # Graceful stop with 10s timeout

# Option 2: Systemd
sudo systemctl stop scitt-ledger.service
```

#### During System Backup

⚠️  **The service CANNOT automatically resume after system reboots** due to CCF limitations.

After reboot, you must manually restart:
```bash
./docker/maintenance.sh end-maintenance
```

#### Manual Maintenance Stop

```bash
# Use the maintenance helper for safe shutdown
./docker/maintenance.sh start-maintenance

# After maintenance, restart fresh
./docker/maintenance.sh end-maintenance
```

**Legacy method (not recommended):**
```bash
# Stop and prevent auto-restart during maintenance
docker update --restart=no scitt-service
docker stop scitt-service

# After maintenance - MUST clean and restart
docker rm scitt-service
docker volume rm scitt-service-vol
export PLATFORM=<virtual|sgx>
./docker/run-service.sh
```

#### Testing Restart Policy

```bash
# Simulate crash (container will auto-restart)
docker kill scitt-service

# Check restart count
docker inspect scitt-service | grep -A 5 RestartCount

# View restart history
docker events --filter 'container=scitt-service' --since 1h
```

### Health Monitoring

Add to your monitoring/cron:

```bash
#!/bin/bash
# Check if service is healthy
if ! docker ps | grep -q scitt-service; then
    echo "ALERT: SCITT service is down!"
    # Send notification or restart
    docker start scitt-service
fi
```

## Security Notes

- The service runs with host networking by default (`--network=host`)
- Workspace files contain cryptographic keys - protect them appropriately
- For production, consider using proper secrets management
- Review and adjust the dev-config.json for production requirements
- Consider running backups when service is stopped to ensure data consistency


