#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# Maintenance helper script for SCITT Contract Ledger Service

set -e

CONTAINER_NAME="${CONTAINER_NAME:-scitt-service}"

show_help() {
    cat << EOF
SCITT Service Maintenance Helper

Usage: $0 <command>

Commands:
    start-maintenance   Stop service and disable auto-restart (safe for backups)
    end-maintenance     Re-enable auto-restart and start service
    backup              Create a backup of the service volume
    restore <file>      Restore from a backup file
    health-check        Check if service is healthy
    restart-stats       Show restart statistics

Examples:
    # Before system maintenance
    $0 start-maintenance

    # After system maintenance
    $0 end-maintenance

    # Create a backup
    $0 backup

    # Check service health
    $0 health-check
EOF
}

check_container_exists() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "❌ Container '$CONTAINER_NAME' does not exist"
        echo "   Run: export PLATFORM=virtual && ./docker/run-service.sh"
        exit 1
    fi
}

start_maintenance() {
    echo "🔧 Starting maintenance mode..."
    check_container_exists
    
    echo "  1. Disabling auto-restart..."
    docker update --restart=no "$CONTAINER_NAME"
    
    echo "  2. Stopping service gracefully..."
    docker stop "$CONTAINER_NAME" || true
    
    echo ""
    echo "✅ Maintenance mode active"
    echo "   Service is stopped and will NOT auto-restart"
    echo "   Safe to perform backups, system maintenance, etc."
    echo ""
    echo "   To resume: $0 end-maintenance"
}

end_maintenance() {
    echo "🔧 Ending maintenance mode..."
    check_container_exists
    
    echo ""
    echo "⚠️  CCF requires a clean start after maintenance"
    echo "   The ledger data will be removed and service will start fresh"
    echo ""
    read -p "   Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Cancelled. Service remains stopped."
        exit 0
    fi
    
    echo ""
    echo "  1. Removing old container and volume..."
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    VOLUME_NAME="${CONTAINER_NAME}-vol"
    docker volume rm "$VOLUME_NAME" 2>/dev/null || true
    
    echo "  2. Starting fresh service..."
    PLATFORM=${PLATFORM:-virtual}
    export PLATFORM
    "$(dirname "$0")/run-service.sh"
}

backup() {
    echo "💾 Creating backup..."
    check_container_exists
    
    VOLUME_NAME="${CONTAINER_NAME}-vol"
    BACKUP_DIR="backups"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="${BACKUP_DIR}/scitt-backup-${TIMESTAMP}.tar.gz"
    
    mkdir -p "$BACKUP_DIR"
    
    echo "  Checking if service should be stopped..."
    IS_RUNNING=$(docker ps --format '{{.Names}}' | grep "^${CONTAINER_NAME}$" || echo "")
    
    if [ -n "$IS_RUNNING" ]; then
        echo "  ⚠️  Service is running. For consistent backup, stop it first:"
        echo "     $0 start-maintenance"
        echo ""
        read -p "  Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "  Backup cancelled"
            exit 1
        fi
    fi
    
    echo "  Exporting volume data..."
    docker run --rm \
        -v "$VOLUME_NAME":/source:ro \
        -v "$(pwd)/$BACKUP_DIR":/backup \
        alpine \
        tar -czf "/backup/scitt-backup-${TIMESTAMP}.tar.gz" -C /source .
    
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    
    echo ""
    echo "✅ Backup complete"
    echo "   File: $BACKUP_FILE"
    echo "   Size: $BACKUP_SIZE"
    echo ""
    echo "   To restore: $0 restore $BACKUP_FILE"
}

restore() {
    BACKUP_FILE="$1"
    
    if [ -z "$BACKUP_FILE" ]; then
        echo "❌ Please specify a backup file"
        echo "   Usage: $0 restore <backup-file>"
        exit 1
    fi
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "❌ Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    echo "🔄 Restoring from backup..."
    check_container_exists
    
    VOLUME_NAME="${CONTAINER_NAME}-vol"
    
    echo "  ⚠️  This will overwrite current data!"
    read -p "  Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "  Restore cancelled"
        exit 1
    fi
    
    echo "  Stopping service..."
    docker stop "$CONTAINER_NAME" || true
    
    echo "  Restoring volume data..."
    docker run --rm \
        -v "$VOLUME_NAME":/target \
        -v "$(pwd)/$(dirname "$BACKUP_FILE")":/backup:ro \
        alpine \
        sh -c "rm -rf /target/* && tar -xzf /backup/$(basename "$BACKUP_FILE") -C /target"
    
    echo "  Starting service..."
    docker start "$CONTAINER_NAME"
    
    echo ""
    echo "✅ Restore complete"
    echo "   Service restarted with restored data"
}

health_check() {
    echo "🏥 Running health check..."
    check_container_exists
    
    # Check if container is running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "  ✅ Container is running"
        
        # Check restart count
        RESTART_COUNT=$(docker inspect "$CONTAINER_NAME" --format='{{.RestartCount}}')
        echo "  ℹ️  Restart count: $RESTART_COUNT"
        
        # Check uptime
        STARTED_AT=$(docker inspect "$CONTAINER_NAME" --format='{{.State.StartedAt}}')
        echo "  ℹ️  Started at: $STARTED_AT"
        
        # Check restart policy
        RESTART_POLICY=$(docker inspect "$CONTAINER_NAME" --format='{{.HostConfig.RestartPolicy.Name}}')
        echo "  ℹ️  Restart policy: $RESTART_POLICY"
        
        # Check if service responds
        CCF_PORT=${CCF_PORT:-8000}
        if curl -s -f -k "https://localhost:${CCF_PORT}/node/network" > /dev/null 2>&1; then
            echo "  ✅ Service is responding on port $CCF_PORT"
            echo ""
            echo "✅ Service is healthy"
            exit 0
        else
            echo "  ⚠️  Service not responding on port $CCF_PORT"
            echo ""
            echo "⚠️  Container running but service not responding"
            echo "   Check logs: docker logs $CONTAINER_NAME"
            exit 1
        fi
    else
        echo "  ❌ Container is not running"
        
        # Check if it exited
        EXIT_CODE=$(docker inspect "$CONTAINER_NAME" --format='{{.State.ExitCode}}' 2>/dev/null || echo "unknown")
        if [ "$EXIT_CODE" != "0" ] && [ "$EXIT_CODE" != "unknown" ]; then
            echo "  ❌ Last exit code: $EXIT_CODE"
            echo ""
            echo "❌ Service is down"
            echo "   Check logs: docker logs $CONTAINER_NAME"
            echo "   Start: ./docker/service-manager.sh start"
            exit 1
        fi
        
        echo ""
        echo "❌ Service is down"
        exit 1
    fi
}

restart_stats() {
    echo "📊 Restart Statistics..."
    check_container_exists
    
    echo ""
    echo "Container: $CONTAINER_NAME"
    echo "---"
    
    docker inspect "$CONTAINER_NAME" --format='
Restart Count:    {{.RestartCount}}
Restart Policy:   {{.HostConfig.RestartPolicy.Name}}
Max Retry Count:  {{.HostConfig.RestartPolicy.MaximumRetryCount}}

State:            {{.State.Status}}
Running:          {{.State.Running}}
Started At:       {{.State.StartedAt}}
Finished At:      {{.State.FinishedAt}}
Exit Code:        {{.State.ExitCode}}
'
    
    echo "Recent Events:"
    echo "---"
    docker events --filter "container=$CONTAINER_NAME" --since 24h --until 1s 2>/dev/null | tail -10 || echo "  No recent events"
}

# Main command dispatcher
case "${1:-}" in
    start-maintenance)
        start_maintenance
        ;;
    end-maintenance)
        end_maintenance
        ;;
    backup)
        backup
        ;;
    restore)
        restore "$2"
        ;;
    health-check)
        health_check
        ;;
    restart-stats)
        restart_stats
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac

