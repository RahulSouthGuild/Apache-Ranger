#!/bin/bash

echo "=================================================="
echo "Testing LDAP Integration with Ranger and Doris"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
test_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
    fi
}

echo ""
echo "1. Checking LDAP Service..."
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -b "dc=example,dc=com" "(objectClass=*)" dn 2>/dev/null | head -5 > /dev/null
test_result $? "LDAP service is accessible"

echo ""
echo "2. Verifying LDAP Users..."
echo "   Users in LDAP:"
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -b "ou=users,dc=example,dc=com" "(objectClass=inetOrgPerson)" uid | grep "^uid:" | cut -d' ' -f2

echo ""
echo "3. Verifying LDAP Groups..."
echo "   Groups in LDAP:"
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -b "ou=groups,dc=example,dc=com" "(objectClass=posixGroup)" cn | grep "^cn:" | cut -d' ' -f2

echo ""
echo "4. Checking Ranger Admin..."
curl -s -u admin:rangerR0cks! http://localhost:6080/service/public/v2/api/service/count > /dev/null
test_result $? "Ranger Admin is accessible"

echo ""
echo "5. Checking Users in Ranger..."
echo "   Fetching users synced to Ranger:"
curl -s -u admin:rangerR0cks! http://localhost:6080/service/xusers/users | python3 -m json.tool | grep -A1 '"name"' | grep -v "^--$" | head -10

echo ""
echo "6. Testing Doris LDAP Authentication..."
echo "   Testing with LDAP user john.doe:"
export LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN=1
mysql -h127.0.0.1 -P9031 -ujohn.doe -ppassword123 -e "SELECT CURRENT_USER();" 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ LDAP authentication successful for john.doe${NC}"
else
    echo -e "${YELLOW}⚠ LDAP authentication might need more configuration${NC}"
fi

echo ""
echo "7. Checking phpLDAPadmin..."
curl -s http://localhost:6081 > /dev/null
test_result $? "phpLDAPadmin is accessible at http://localhost:6081"

echo ""
echo "=================================================="
echo "Test Summary:"
echo "- LDAP Server: http://localhost:389"
echo "- phpLDAPadmin: http://localhost:6081"
echo "  Login: cn=admin,dc=example,dc=com / admin123"
echo "- Ranger Admin: http://localhost:6080"
echo "  Login: admin / rangerR0cks!"
echo "- Doris FE: http://localhost:8031"
echo ""
echo "LDAP Test Users:"
echo "  - john.doe / password123"
echo "  - jane.smith / password123"
echo "  - admin.user / admin123"
echo "  - data.analyst / password123"
echo "=================================================="