#!/bin/bash

# Wrapper script to run LDAP-Doris sync with periodic connection cleanup

SYNC_SCRIPT="/home/rahul/RahulSouthGuild/Apache-Ranger/scripts/ldap-doris-sync.sh"
CLEANUP_SCRIPT="/home/rahul/RahulSouthGuild/Apache-Ranger/scripts/cleanup-doris-connections.sh"
CLEANUP_INTERVAL=300  # Clean up connections every 5 minutes

echo "Starting LDAP-Doris sync with automatic connection cleanup"
echo "Cleanup will run every $CLEANUP_INTERVAL seconds"

# Function to cleanup connections
cleanup_connections() {
    echo "[$(date)] Running connection cleanup..."
    $CLEANUP_SCRIPT
}

# Trap to cleanup on exit
trap cleanup_connections EXIT

# Start the sync script in background
$SYNC_SCRIPT continuous &
SYNC_PID=$!

# Periodically clean up connections
while kill -0 $SYNC_PID 2>/dev/null; do
    sleep $CLEANUP_INTERVAL
    cleanup_connections
done

echo "Sync script stopped"