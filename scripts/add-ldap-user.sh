#!/bin/bash

# Script to add a new user to LDAP
# Usage: ./add-ldap-user.sh <username> <firstname> <lastname> <password> [group]

if [ $# -lt 4 ]; then
    echo "Usage: $0 <username> <firstname> <lastname> <password> [group]"
    echo "Example: $0 testuser Test User TestPass123! data-analysts"
    exit 1
fi

USERNAME=$1
FIRSTNAME=$2
LASTNAME=$3
PASSWORD=$4
GROUP=${5:-users}  # Default to 'users' group if not specified

# Generate a unique UID number
LAST_UID=$(ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -b "ou=users,dc=example,dc=com" "(objectClass=inetOrgPerson)" uidNumber 2>/dev/null | grep "^uidNumber:" | cut -d' ' -f2 | sort -n | tail -1)
NEW_UID=$((LAST_UID + 1))

# Create LDIF file for new user
cat > /tmp/new_user.ldif <<EOF
dn: uid=${USERNAME},ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: ${USERNAME}
sn: ${LASTNAME}
givenName: ${FIRSTNAME}
cn: ${FIRSTNAME} ${LASTNAME}
displayName: ${FIRSTNAME} ${LASTNAME}
uidNumber: ${NEW_UID}
gidNumber: 10001
userPassword: ${PASSWORD}
gecos: ${FIRSTNAME} ${LASTNAME}
loginShell: /bin/bash
homeDirectory: /home/${USERNAME}
mail: ${USERNAME}@example.com
EOF

echo "Adding user ${USERNAME} to LDAP..."
ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -f /tmp/new_user.ldif

if [ $? -eq 0 ]; then
    echo "User ${USERNAME} added successfully!"

    # Add user to group if specified
    if [ "$GROUP" != "users" ]; then
        echo "Adding ${USERNAME} to group ${GROUP}..."
        cat > /tmp/add_to_group.ldif <<EOF
dn: cn=${GROUP},ou=groups,dc=example,dc=com
changetype: modify
add: memberUid
memberUid: ${USERNAME}
EOF
        ldapmodify -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -f /tmp/add_to_group.ldif

        if [ $? -eq 0 ]; then
            echo "User ${USERNAME} added to group ${GROUP}"
        else
            echo "Failed to add user to group ${GROUP}"
        fi
    fi

    # Clean up
    rm -f /tmp/new_user.ldif /tmp/add_to_group.ldif

    echo ""
    echo "User created with credentials:"
    echo "  Username: ${USERNAME}"
    echo "  Password: ${PASSWORD}"
    echo "  Group: ${GROUP}"
    echo ""
    echo "Wait 5 minutes for Ranger UserSync to synchronize, then test with:"
    echo "  mysql -h127.0.0.1 -P9031 -u${USERNAME} -p${PASSWORD}"
    echo ""
else
    echo "Failed to add user ${USERNAME}"
    rm -f /tmp/new_user.ldif
    exit 1
fi