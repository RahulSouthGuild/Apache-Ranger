#!/bin/bash

# Script to sync LDAP users to Doris
# This creates Doris users matching LDAP users

echo "=== Syncing LDAP Users to Doris ==="

# Get all users from LDAP
LDAP_USERS=$(docker exec openldap ldapsearch -x -H ldap://localhost:389 \
    -D "cn=admin,dc=example,dc=com" -w admin123 \
    -b "ou=users,dc=example,dc=com" "(objectClass=inetOrgPerson)" uid 2>/dev/null | \
    grep "^uid:" | cut -d' ' -f2)

echo "Found LDAP users: $LDAP_USERS"

for user in $LDAP_USERS; do
    echo "Processing user: $user"

    # Check if user exists in Doris
    USER_EXISTS=$(docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e \
        "SELECT COUNT(*) FROM mysql.user WHERE User='$user';" 2>/dev/null)

    if [ "$USER_EXISTS" = "0" ]; then
        echo "  Creating user $user in Doris..."

        # Get user's group from LDAP
        GROUPS=$(docker exec openldap ldapsearch -x -H ldap://localhost:389 \
            -D "cn=admin,dc=example,dc=com" -w admin123 \
            -b "ou=groups,dc=example,dc=com" "(memberUid=$user)" cn 2>/dev/null | \
            grep "^cn:" | cut -d' ' -f2)

        # Set permissions based on group
        if echo "$GROUPS" | grep -q "admins\|ranger-admins"; then
            GRANT_STMT="GRANT ALL ON *.* TO '$user'@'%';"
            echo "  Admin user - granting all privileges"
        elif echo "$GROUPS" | grep -q "data-analysts"; then
            GRANT_STMT="GRANT SELECT, INSERT, UPDATE ON *.* TO '$user'@'%';"
            echo "  Data analyst - granting read/write privileges"
        else
            GRANT_STMT="GRANT SELECT ON *.* TO '$user'@'%';"
            echo "  Regular user - granting read-only privileges"
        fi

        # Create user in Doris with a default password
        # In production, you'd want to use the actual LDAP password or a different auth mechanism
        docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e "
            CREATE USER '$user'@'%' IDENTIFIED BY 'password123';
            $GRANT_STMT
        " 2>&1 | grep -v "Warning"

        if [ $? -eq 0 ]; then
            echo "  ✓ User $user created successfully"
        else
            echo "  ✗ Failed to create user $user (might be due to Ranger/LDAP conflict)"
        fi
    else
        echo "  User $user already exists in Doris"
    fi
done

echo ""
echo "=== Sync Complete ==="

# Show current Doris users
echo "Current Doris users:"
docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e \
    "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'admin');" 2>/dev/null | \
    while read user; do
        echo "  - $user"
    done