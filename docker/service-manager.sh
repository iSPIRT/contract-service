#!/bin/bash
# Service management wrapper for SCITT Contract Ledger

CONTAINER_NAME=${CONTAINER_NAME:-"scitt-service"}
VOLUME_NAME="${CONTAINER_NAME}-vol"

case "$1" in
    start)
        if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "Starting existing container..."
            docker start "$CONTAINER_NAME"
        else
            echo "Container doesn't exist. Run the initial setup first:"
            echo "  export PLATFORM=virtual"
            echo "  ./docker/build.sh"
            echo "  ./docker/run-service.sh"
            exit 1
        fi
        ;;
    stop)
        echo "Stopping service..."
        docker stop "$CONTAINER_NAME"
        ;;
    restart)
        echo "⚠️  CCF cannot restart with existing ledger data"
        echo "   This will remove all ledger history and start fresh."
        echo ""
        read -p "   Continue with full restart? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "   Cancelled"
            exit 0
        fi
        
        echo ""
        echo "🔄 Performing full restart..."
        
        # Stop and remove container
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        
        # Remove volume
        docker volume rm "$VOLUME_NAME" 2>/dev/null || true
        
        # Restart the service
        echo "   Running startup script..."
        PLATFORM=${PLATFORM:-virtual}
        export PLATFORM
        "$(dirname "$0")/run-service.sh"
        ;;
    status)
        if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "✅ Service is running"
            docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            echo "⚠️  Service exists but is not running"
            docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}"
        else
            echo "❌ Service not found"
        fi
        ;;
    logs)
        docker logs -f "$CONTAINER_NAME"
        ;;
    remove)
        echo "Removing service completely..."
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        docker volume rm "$VOLUME_NAME" 2>/dev/null || true
        echo "✅ Service removed"
        ;;
    *)
        echo "SCITT Service Manager"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs|remove}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the service"
        echo "  stop    - Stop the service"
        echo "  restart - Restart the service"
        echo "  status  - Check service status"
        echo "  logs    - View service logs (live)"
        echo "  remove  - Stop and remove the service completely"
        echo ""
        echo "First-time setup:"
        echo "  export PLATFORM=virtual"
        echo "  ./docker/build.sh"
        echo "  ./docker/run-service.sh"
        exit 1
        ;;
esac


