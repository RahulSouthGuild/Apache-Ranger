#!/bin/bash

# LDAP to Ranger User Sync Script
# This script syncs users and groups from LDAP to Apache Ranger

echo "[$(date)] Starting LDAP to Ranger sync..."

# Configuration from environment variables
LDAP_URL="${SYNC_LDAP_URL:-ldap://openldap:389}"
LDAP_BIND_DN="${SYNC_LDAP_BIND_DN:-cn=admin,dc=example,dc=com}"
LDAP_BIND_PASSWORD="${SYNC_LDAP_BIND_PASSWORD:-admin123}"
LDAP_USER_BASE="${SYNC_LDAP_USER_SEARCH_BASE:-ou=users,dc=example,dc=com}"
LDAP_GROUP_BASE="${SYNC_GROUP_SEARCH_BASE:-ou=groups,dc=example,dc=com}"
RANGER_URL="${POLICY_MGR_URL:-http://ranger:6080}"
RANGER_USER="${RANGER_ADMIN_USERNAME:-admin}"
RANGER_PASSWORD="${RANGER_ADMIN_PASSWORD:-rangerR0cks!}"

# Wait for services to be ready
until nc -z openldap 389 2>/dev/null; do
    echo "[$(date)] Waiting for LDAP..."
    sleep 5
done

until curl -s -u "$RANGER_USER:$RANGER_PASSWORD" "$RANGER_URL/service/xusers/users" > /dev/null 2>&1; do
    echo "[$(date)] Waiting for Ranger Admin..."
    sleep 5
done

echo "[$(date)] Services are ready. Starting sync..."

# Function to create user in Ranger
create_ranger_user() {
    local username=$1
    local firstname=$2
    local lastname=$3
    local email=$4

    echo "[$(date)] Creating/updating user: $username"

    # Check if user exists
    USER_EXISTS=$(curl -s -u "$RANGER_USER:$RANGER_PASSWORD" \
        "$RANGER_URL/service/xusers/users/userName/$username" 2>/dev/null | grep -c "\"name\":\"$username\"")

    if [ "$USER_EXISTS" -eq 0 ]; then
        # Create new user
        curl -s -X POST -u "$RANGER_USER:$RANGER_PASSWORD" \
            -H "Content-Type: application/json" \
            "$RANGER_URL/service/xusers/secure/users" \
            -d "{
                \"name\": \"$username\",
                \"firstName\": \"$firstname\",
                \"lastName\": \"$lastname\",
                \"emailAddress\": \"$email\",
                \"password\": \"Pass123!\",
                \"userRoleList\": [\"ROLE_USER\"],
                \"status\": 1
            }" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "[$(date)] User $username created successfully"
        else
            echo "[$(date)] Failed to create user $username"
        fi
    else
        echo "[$(date)] User $username already exists"
    fi
}

# Function to create group in Ranger
create_ranger_group() {
    local groupname=$1
    local description=$2

    echo "[$(date)] Creating/updating group: $groupname"

    # Check if group exists
    GROUP_EXISTS=$(curl -s -u "$RANGER_USER:$RANGER_PASSWORD" \
        "$RANGER_URL/service/xusers/groups/groupName/$groupname" 2>/dev/null | grep -c "\"name\":\"$groupname\"")

    if [ "$GROUP_EXISTS" -eq 0 ]; then
        # Create new group
        curl -s -X POST -u "$RANGER_USER:$RANGER_PASSWORD" \
            -H "Content-Type: application/json" \
            "$RANGER_URL/service/xusers/secure/groups" \
            -d "{
                \"name\": \"$groupname\",
                \"description\": \"$description\"
            }" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "[$(date)] Group $groupname created successfully"
        else
            echo "[$(date)] Failed to create group $groupname"
        fi
    else
        echo "[$(date)] Group $groupname already exists"
    fi
}

# Function to add user to group in Ranger
add_user_to_group() {
    local username=$1
    local groupname=$2

    echo "[$(date)] Adding user $username to group $groupname"

    # Get user ID
    USER_ID=$(curl -s -u "$RANGER_USER:$RANGER_PASSWORD" \
        "$RANGER_URL/service/xusers/users/userName/$username" 2>/dev/null | \
        grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

    # Get group ID
    GROUP_ID=$(curl -s -u "$RANGER_USER:$RANGER_PASSWORD" \
        "$RANGER_URL/service/xusers/groups/groupName/$groupname" 2>/dev/null | \
        grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

    if [ -n "$USER_ID" ] && [ -n "$GROUP_ID" ]; then
        curl -s -X POST -u "$RANGER_USER:$RANGER_PASSWORD" \
            -H "Content-Type: application/json" \
            "$RANGER_URL/service/xusers/secure/groups/$GROUP_ID/users" \
            -d "[\"$username\"]" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "[$(date)] Added $username to group $groupname"
        fi
    fi
}

# Sync users from LDAP
echo "[$(date)] Syncing users from LDAP..."
ldapsearch -x -H "$LDAP_URL" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
    -b "$LDAP_USER_BASE" "(objectClass=inetOrgPerson)" \
    uid givenName sn mail 2>/dev/null | \
    awk '
        /^uid:/ {uid=$2}
        /^givenName:/ {givenName=$2}
        /^sn:/ {sn=$2}
        /^mail:/ {mail=$2}
        /^$/ {
            if (uid) {
                print uid"|"givenName"|"sn"|"mail
                uid=""; givenName=""; sn=""; mail=""
            }
        }
    ' | while IFS='|' read -r username firstname lastname email; do
        if [ -n "$username" ]; then
            create_ranger_user "$username" "${firstname:-$username}" "${lastname:-User}" "${email:-$username@example.com}"
        fi
    done

# Sync groups from LDAP
echo "[$(date)] Syncing groups from LDAP..."
ldapsearch -x -H "$LDAP_URL" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
    -b "$LDAP_GROUP_BASE" "(objectClass=posixGroup)" \
    cn description 2>/dev/null | \
    awk '
        /^cn:/ {cn=$2}
        /^description:/ {description=$0; gsub(/^description: /, "", description)}
        /^$/ {
            if (cn) {
                print cn"|"description
                cn=""; description=""
            }
        }
    ' | while IFS='|' read -r groupname description; do
        if [ -n "$groupname" ]; then
            create_ranger_group "$groupname" "${description:-LDAP Group}"
        fi
    done

# Sync group memberships
echo "[$(date)] Syncing group memberships..."
ldapsearch -x -H "$LDAP_URL" -D "$LDAP_BIND_DN" -w "$LDAP_BIND_PASSWORD" \
    -b "$LDAP_GROUP_BASE" "(objectClass=posixGroup)" \
    cn memberUid 2>/dev/null | \
    awk '
        /^cn:/ {cn=$2; members=""}
        /^memberUid:/ {if (members) members=members","; members=members$2}
        /^$/ {
            if (cn && members) {
                print cn"|"members
                cn=""; members=""
            }
        }
    ' | while IFS='|' read -r groupname members; do
        if [ -n "$groupname" ] && [ -n "$members" ]; then
            IFS=',' read -ra MEMBERS <<< "$members"
            for member in "${MEMBERS[@]}"; do
                add_user_to_group "$member" "$groupname"
            done
        fi
    done

echo "[$(date)] LDAP to Ranger sync completed"

# Show summary
USER_COUNT=$(curl -s -u "$RANGER_USER:$RANGER_PASSWORD" "$RANGER_URL/service/xusers/users" 2>/dev/null | grep -o '"totalCount":[0-9]*' | cut -d: -f2)
GROUP_COUNT=$(curl -s -u "$RANGER_USER:$RANGER_PASSWORD" "$RANGER_URL/service/xusers/groups" 2>/dev/null | grep -o '"totalCount":[0-9]*' | cut -d: -f2)

echo "[$(date)] Summary: $USER_COUNT users and $GROUP_COUNT groups in Ranger"