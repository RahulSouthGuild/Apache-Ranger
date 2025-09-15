#!/bin/bash

# Script to start LDAP-Doris sync in background with proper logging

SYNC_SCRIPT="/home/rahul/RahulSouthGuild/Apache-Ranger/scripts/ldap-doris-sync.sh"
LOG_FILE="/tmp/ldap-doris-sync-daemon.log"
PID_FILE="/tmp/ldap-doris-sync.pid"

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "LDAP-Doris sync is already running with PID $OLD_PID"
        exit 0
    else
        echo "Removing stale PID file"
        rm -f "$PID_FILE"
    fi
fi

echo "Starting LDAP-Doris automatic sync service..."
echo "Sync will run every 30 seconds"
echo "Logs: $LOG_FILE"
echo "PID file: $PID_FILE"

# Start sync in background
nohup $SYNC_SCRIPT continuous > "$LOG_FILE" 2>&1 &
SYNC_PID=$!

# Save PID
echo $SYNC_PID > "$PID_FILE"

echo "LDAP-Doris sync started with PID $SYNC_PID"
echo ""
echo "To check status: ps -p $SYNC_PID"
echo "To view logs: tail -f $LOG_FILE"
echo "To stop: kill $SYNC_PID"
echo ""
echo "Sync is now running automatically in the background!"
