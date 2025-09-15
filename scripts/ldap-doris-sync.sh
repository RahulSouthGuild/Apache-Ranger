#!/bin/bash

# LDAP to Doris User Sync Script
# This script polls LDAP for users and automatically creates them in Doris
# It runs continuously and checks for new users every minute

# Configuration
LDAP_HOST="openldap"
LDAP_PORT="389"
LDAP_BIND_DN="cn=admin,dc=example,dc=com"
LDAP_BIND_PASSWORD="admin123"
LDAP_USER_BASE="ou=users,dc=example,dc=com"
LDAP_GROUP_BASE="ou=groups,dc=example,dc=com"

DORIS_HOST="127.0.0.1"
DORIS_PORT="9030"
DORIS_USER="root"
DORIS_PASSWORD=""

# Sync interval in seconds (default: 30 seconds)
SYNC_INTERVAL=${SYNC_INTERVAL:-30}

# Log file
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

# Function to get all LDAP users with their details
get_ldap_users() {
    docker exec openldap ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" \
        -D "${LDAP_BIND_DN}" -w "${LDAP_BIND_PASSWORD}" \
        -b "${LDAP_USER_BASE}" "(objectClass=inetOrgPerson)" \
        uid userPassword 2>/dev/null | \
    awk '
        /^uid:/ {uid=$2}
        /^userPassword:/ {
            # Extract password - handle different formats
            password=$2
            # If password is in {SSHA} or plain format, use a default
            if (match(password, /^\{.*\}/)) {
                # Hashed password, use default
                password="password123"
            } else if (password == "") {
                password="password123"
            }
        }
        /^$/ {
            if (uid) {
                print uid"|"password
                uid=""; password="password123"
            }
        }
    '
}

# Function to get user's groups from LDAP
get_user_groups() {
    local username=$1
    docker exec openldap ldapsearch -x -H "ldap://${LDAP_HOST}:${LDAP_PORT}" \
        -D "${LDAP_BIND_DN}" -w "${LDAP_BIND_PASSWORD}" \
        -b "${LDAP_GROUP_BASE}" "(memberUid=${username})" cn 2>/dev/null | \
        grep "^cn:" | cut -d' ' -f2 | tr '\n' ',' | sed 's/,$//'
}

# Function to check if user exists in Doris
user_exists_in_doris() {
    local username=$1
    local result=$(docker exec doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
        -u"${DORIS_USER}" -N -e \
        "SELECT COUNT(*) FROM mysql.user WHERE User='${username}';" 2>/dev/null)

    [ "$result" = "1" ]
}

# Function to create user in Doris
create_doris_user() {
    local username=$1
    local password=$2
    local groups=$3

    # For LDAP users, we'll use their LDAP password or a default
    # In production, you might want to use a different authentication method

    log_message "Creating user '${username}' in Doris..."

    # Create the user (Doris root has no password, so don't use -p flag)
    # First create the user
    docker exec doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
        -u"${DORIS_USER}" -e \
        "CREATE USER IF NOT EXISTS '${username}'@'%';" 2>&1 | \
        grep -v "Warning" >> "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        # Immediately set the password using SET PASSWORD (works better in Doris)
        docker exec doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
            -u"${DORIS_USER}" -e \
            "SET PASSWORD FOR '${username}'@'%' = PASSWORD('${password}');" 2>&1 | \
            grep -v "Warning" >> "$LOG_FILE"

        log_message "  ${GREEN}✓${NC} User '${username}' created and password set successfully"
        log_message "  Groups: ${groups:-none}"
        return 0
    else
        log_message "  ${RED}✗${NC} Failed to create user '${username}'"
        return 1
    fi
}

# Function to update user password in Doris (if changed)
update_doris_user_password() {
    local username=$1
    local password=$2

    log_message "Updating password for user '${username}'..."

    docker exec doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
        -u"${DORIS_USER}" -e \
        "ALTER USER '${username}'@'%' IDENTIFIED BY '${password}';" 2>&1 | \
        grep -v "Warning" >> "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_message "  ${GREEN}✓${NC} Password updated for '${username}'"
        return 0
    else
        log_message "  ${YELLOW}⚠${NC} Could not update password for '${username}'"
        return 1
    fi
}

# Function to sync a single user
sync_user() {
    local username=$1
    local password=$2

    # Get user's groups
    local groups=$(get_user_groups "$username")

    if user_exists_in_doris "$username"; then
        # User exists, optionally update password
        # Uncomment the next line if you want to sync password changes
        # update_doris_user_password "$username" "$password"
        echo -e "${BLUE}[SKIP]${NC} User '$username' already exists in Doris"
    else
        # User doesn't exist, create it
        echo -e "${GREEN}[NEW]${NC} Creating user '$username' in Doris"
        create_doris_user "$username" "$password" "$groups"
    fi
}

# Function to perform one sync cycle
sync_cycle() {
    log_message "Starting LDAP to Doris sync cycle..."

    # Get all LDAP users
    local ldap_users=$(get_ldap_users)
    local user_count=$(echo "$ldap_users" | grep -c "|")

    log_message "Found ${user_count} users in LDAP"

    # Track statistics
    local new_users=0
    local existing_users=0
    local failed_users=0

    # Process each user
    while IFS='|' read -r username password; do
        if [ -n "$username" ]; then
            if user_exists_in_doris "$username"; then
                ((existing_users++))
                echo -e "  ${BLUE}[EXISTS]${NC} $username"
                # Password is fixed separately using fix-doris-passwords.sh script
                # Auto password setting disabled to avoid overriding fixed passwords
            else
                if create_doris_user "$username" "$password" "$(get_user_groups $username)"; then
                    ((new_users++))
                else
                    ((failed_users++))
                fi
            fi
        fi
    done <<< "$ldap_users"

    # Summary
    log_message "Sync cycle complete:"
    log_message "  - New users created: ${new_users}"
    log_message "  - Existing users: ${existing_users}"
    log_message "  - Failed: ${failed_users}"

    # Show current Doris users
    echo -e "\n${BLUE}Current Doris users:${NC}"
    docker exec doris-fe-01 mysql -h"${DORIS_HOST}" -P"${DORIS_PORT}" \
        -u"${DORIS_USER}" -p"${DORIS_PASSWORD}" -N -e \
        "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'admin');" 2>/dev/null | \
        while read user; do
            echo "  - $user"
        done
}

# Function to run continuous sync
run_continuous_sync() {
    log_message "Starting continuous LDAP to Doris sync service"
    log_message "Sync interval: ${SYNC_INTERVAL} seconds"
    log_message "Press Ctrl+C to stop"

    while true; do
        echo -e "\n${YELLOW}========================================${NC}"
        echo -e "${YELLOW}$(date '+%Y-%m-%d %H:%M:%S') - Sync Cycle${NC}"
        echo -e "${YELLOW}========================================${NC}"

        sync_cycle

        echo -e "\n${BLUE}Sleeping for ${SYNC_INTERVAL} seconds...${NC}"
        sleep "${SYNC_INTERVAL}"
    done
}

# Function to run one-time sync
run_once() {
    echo -e "${YELLOW}Running one-time LDAP to Doris sync${NC}"
    sync_cycle
}

# Main script
main() {
    # Check if running in Docker or host
    if [ -f /.dockerenv ]; then
        # Running inside Docker container
        DOCKER_PREFIX=""
    else
        # Running on host, use docker exec
        DOCKER_PREFIX="docker exec"
    fi

    # Parse command line arguments
    case "${1:-}" in
        once)
            run_once
            ;;
        continuous)
            run_continuous_sync
            ;;
        *)
            echo "Usage: $0 [once|continuous]"
            echo "  once       - Run sync once and exit"
            echo "  continuous - Run sync continuously (default)"
            echo ""
            echo "Environment variables:"
            echo "  SYNC_INTERVAL - Sync interval in seconds (default: 60)"
            echo ""
            run_continuous_sync
            ;;
    esac
}

# Handle script termination
trap 'log_message "Sync service stopped"; exit 0' INT TERM

# Run main function
main "$@"