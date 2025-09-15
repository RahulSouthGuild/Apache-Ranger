#!/bin/bash

# Optimized LDAP to Doris sync script with connection pooling
# This version minimizes database connections to prevent connection limit issues

set -e

# Configuration
LDAP_HOST="${LDAP_HOST:-localhost}"
LDAP_PORT="${LDAP_PORT:-389}"
LDAP_BIND_DN="${LDAP_BIND_DN:-cn=admin,dc=example,dc=com}"
LDAP_BIND_PASSWORD="${LDAP_BIND_PASSWORD:-admin123}"
LDAP_USER_BASE="${LDAP_USER_BASE:-ou=users,dc=example,dc=com}"
LDAP_GROUP_BASE="${LDAP_GROUP_BASE:-ou=groups,dc=example,dc=com}"

DORIS_HOST="${DORIS_HOST:-127.0.0.1}"
DORIS_PORT="${DORIS_PORT:-9030}"
DORIS_USER="${DORIS_USER:-root}"
DORIS_PASSWORD="${DORIS_PASSWORD:-}"

SYNC_INTERVAL="${SYNC_INTERVAL:-30}"
LOG_FILE="/tmp/ldap-doris-sync.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to execute batch SQL commands in a single connection
execute_batch_sql() {
    local sql_commands=$1
    if [ -n "$sql_commands" ]; then
        echo "$sql_commands" | docker exec -i doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
            -u"${DORIS_USER}" -p"${DORIS_PASSWORD}" --connect-timeout=5 2>&1 | \
            grep -v "Warning" >> "$LOG_FILE"
        return ${PIPESTATUS[0]}
    fi
    return 0
}

# Function to get all LDAP users
get_ldap_users() {
    docker exec openldap ldapsearch -x -H ldap://"${LDAP_HOST}":"${LDAP_PORT}" \
        -D "${LDAP_BIND_DN}" -w "${LDAP_BIND_PASSWORD}" \
        -b "${LDAP_USER_BASE}" "(objectClass=inetOrgPerson)" uid 2>/dev/null | \
        grep "^uid:" | cut -d' ' -f2 | sort
}

# Function to get all Doris users in a single query
get_doris_users() {
    docker exec doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
        -u"${DORIS_USER}" -p"${DORIS_PASSWORD}" -N --connect-timeout=5 -e \
        "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'admin', 'rahul');" 2>/dev/null | sort
}

# Function to get user's groups
get_user_groups() {
    local username=$1
    docker exec openldap ldapsearch -x -H ldap://"${LDAP_HOST}":"${LDAP_PORT}" \
        -D "${LDAP_BIND_DN}" -w "${LDAP_BIND_PASSWORD}" \
        -b "${LDAP_GROUP_BASE}" "(memberUid=${username})" cn 2>/dev/null | \
        grep "^cn:" | cut -d' ' -f2 | tr '\n' ',' | sed 's/,$//'
}

# Function to perform sync
sync_users() {
    log_message "Starting LDAP to Doris sync cycle..."

    # Get all LDAP users
    local ldap_users=$(get_ldap_users)
    local ldap_user_count=$(echo "$ldap_users" | wc -w)
    log_message "Found $ldap_user_count users in LDAP"

    # Get all existing Doris users in a single query
    local doris_users=$(get_doris_users)

    # Build batch SQL commands
    local sql_commands=""
    local new_users=0
    local existing_users=0
    local failed_users=0

    for username in $ldap_users; do
        if [ -z "$username" ]; then
            continue
        fi

        # Check if user exists in Doris (using cached list)
        if echo "$doris_users" | grep -q "^${username}$"; then
            echo "  ${BLUE}[EXISTS]${NC} $username"
            ((existing_users++))
        else
            # Add to batch create commands
            local groups=$(get_user_groups "$username")
            log_message "Creating user '${username}' in Doris..."

            # Add CREATE USER command to batch
            sql_commands="${sql_commands}CREATE USER IF NOT EXISTS '${username}'@'%' IDENTIFIED BY 'password123';"
            sql_commands="${sql_commands}\n"

            log_message "  ${GREEN}✓${NC} User '${username}' queued for creation"
            log_message "  Groups: ${groups:-none}"
            ((new_users++))
        fi
    done

    # Execute all CREATE USER commands in a single connection
    if [ -n "$sql_commands" ]; then
        log_message "Executing batch user creation..."
        if execute_batch_sql "$sql_commands"; then
            log_message "Batch user creation completed successfully"
        else
            log_message "${RED}Error during batch user creation${NC}"
            ((failed_users++))
        fi
    fi

    # Summary
    log_message "Sync cycle complete:"
    log_message "  - New users created: $new_users"
    log_message "  - Existing users: $existing_users"
    log_message "  - Failed: $failed_users"

    # Show current Doris users (single query)
    echo -e "\n${BLUE}Current Doris users:${NC}"
    get_doris_users | sed 's/^/  - /'
}

# Main execution
MODE="${1:-continuous}"

case "$MODE" in
    once)
        sync_users
        ;;
    continuous)
        log_message "Starting continuous LDAP to Doris sync service"
        log_message "Sync interval: ${SYNC_INTERVAL} seconds"
        log_message "Press Ctrl+C to stop"

        while true; do
            echo -e "\n${YELLOW}========================================${NC}"
            echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - Sync Cycle${NC}"
            echo -e "${YELLOW}========================================${NC}"

            sync_users

            echo -e "\n${BLUE}Sleeping for ${SYNC_INTERVAL} seconds...${NC}"
            sleep "${SYNC_INTERVAL}"
        done
        ;;
    *)
        echo "Usage: $0 [once|continuous]"
        echo "  once       - Run sync once and exit"
        echo "  continuous - Run sync continuously (default)"
        echo ""
        echo "Environment variables:"
        echo "  SYNC_INTERVAL - Sync interval in seconds (default: 30)"
        exit 1
        ;;
esac