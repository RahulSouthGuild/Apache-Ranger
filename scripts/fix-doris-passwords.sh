#!/bin/bash

# Script to fix passwords for all LDAP-synced users in Doris
# This is a workaround for Doris not properly setting passwords during CREATE USER

echo "Fixing passwords for all LDAP-synced users in Doris..."
echo "All users will have password: password123"

# Get all users from LDAP
LDAP_USERS=$(docker exec openldap ldapsearch -x -H ldap://localhost:389 \
    -D "cn=admin,dc=example,dc=com" -w admin123 \
    -b "ou=users,dc=example,dc=com" "(objectClass=inetOrgPerson)" uid 2>/dev/null | \
    grep "^uid:" | cut -d' ' -f2)

# Fix password for each user
for user in $LDAP_USERS; do
    echo -n "Fixing password for $user... "
    docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e \
        "ALTER USER IF EXISTS '$user'@'%' IDENTIFIED BY 'password123';" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "✓"
    else
        echo "✗ (user might not exist in Doris yet)"
    fi
done

echo ""
echo "Password fix complete!"
echo "All synced users can now login with: password123"