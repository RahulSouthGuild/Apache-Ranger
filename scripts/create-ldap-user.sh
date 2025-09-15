#!/bin/bash

# Script to create LDAP user with correct DN structure
# Usage: ./create-ldap-user.sh <username> <firstname> <lastname> <password> [group]

if [ $# -lt 4 ]; then
    echo "Usage: $0 <username> <firstname> <lastname> <password> [group]"
    echo "Example: $0 vineet Vineet Kukreti VineetPass123 data-analysts"
    exit 1
fi

USERNAME=$1
FIRSTNAME=$2
LASTNAME=$3
PASSWORD=$4
GROUP=${5:-users}  # Default to 'users' group

# Generate unique UID number
LAST_UID=$(docker exec openldap ldapsearch -x -H ldap://localhost:389 \
    -D "cn=admin,dc=example,dc=com" -w admin123 \
    -b "ou=users,dc=example,dc=com" "(objectClass=inetOrgPerson)" uidNumber 2>/dev/null | \
    grep "^uidNumber:" | cut -d' ' -f2 | sort -n | tail -1)

NEW_UID=$((LAST_UID + 1))
if [ -z "$LAST_UID" ]; then
    NEW_UID=10010
fi

echo "Creating LDAP user: $USERNAME"
echo "UID Number: $NEW_UID"

# Create LDIF file with correct DN structure
cat > /tmp/create_${USERNAME}.ldif <<EOF
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

# Add user to LDAP
docker cp /tmp/create_${USERNAME}.ldif openldap:/tmp/
docker exec openldap ldapadd -x -H ldap://localhost:389 \
    -D "cn=admin,dc=example,dc=com" -w admin123 \
    -f /tmp/create_${USERNAME}.ldif

if [ $? -eq 0 ]; then
    echo "✓ User $USERNAME created successfully in LDAP"

    # Add to group if specified and group exists
    if [ "$GROUP" != "users" ]; then
        echo "Adding $USERNAME to group $GROUP..."

        # Check if group exists
        GROUP_EXISTS=$(docker exec openldap ldapsearch -x -H ldap://localhost:389 \
            -D "cn=admin,dc=example,dc=com" -w admin123 \
            -b "cn=$GROUP,ou=groups,dc=example,dc=com" cn 2>/dev/null | grep -c "^cn:")

        if [ "$GROUP_EXISTS" -eq 1 ]; then
            cat > /tmp/add_to_${GROUP}.ldif <<EOF
dn: cn=${GROUP},ou=groups,dc=example,dc=com
changetype: modify
add: memberUid
memberUid: ${USERNAME}

dn: cn=${GROUP},ou=groups,dc=example,dc=com
changetype: modify
add: member
member: uid=${USERNAME},ou=users,dc=example,dc=com
EOF

            docker cp /tmp/add_to_${GROUP}.ldif openldap:/tmp/
            docker exec openldap ldapmodify -x -H ldap://localhost:389 \
                -D "cn=admin,dc=example,dc=com" -w admin123 \
                -f /tmp/add_to_${GROUP}.ldif > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo "✓ User $USERNAME added to group $GROUP"
            else
                echo "⚠ Could not add user to group $GROUP (might already be member)"
            fi

            rm -f /tmp/add_to_${GROUP}.ldif
        else
            echo "⚠ Group $GROUP does not exist"
        fi
    fi

    # Clean up
    rm -f /tmp/create_${USERNAME}.ldif

    echo ""
    echo "User created with:"
    echo "  Username: $USERNAME"
    echo "  Password: $PASSWORD"
    echo "  Group: $GROUP"
    echo ""
    echo "The user will appear in Ranger and Doris within 30 seconds."
    echo "Test login: mysql -h127.0.0.1 -P9031 -u$USERNAME -ppassword123"

else
    echo "✗ Failed to create user $USERNAME"
    rm -f /tmp/create_${USERNAME}.ldif
    exit 1
fi