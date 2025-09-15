#!/bin/bash

# Complete Integration Test Script
# Tests LDAP → Ranger → Doris integration

echo "=========================================="
echo "Complete LDAP-Ranger-Doris Integration Test"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name=$1
    local test_command=$2

    echo -n "Testing: $test_name... "

    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo "1. LDAP Tests"
echo "-------------"
run_test "LDAP service is running" "docker exec openldap ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=example,dc=com' -w admin123 -b 'dc=example,dc=com' -s base"
run_test "LDAP has users" "docker exec openldap ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=example,dc=com' -w admin123 -b 'ou=users,dc=example,dc=com' '(objectClass=inetOrgPerson)' uid | grep -q 'uid:'"
run_test "LDAP has groups" "docker exec openldap ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=example,dc=com' -w admin123 -b 'ou=groups,dc=example,dc=com' '(objectClass=posixGroup)' cn | grep -q 'cn:'"

echo ""
echo "2. Ranger Tests"
echo "---------------"
run_test "Ranger Admin is running" "curl -s -u admin:rangerR0cks! http://localhost:6080 > /dev/null"
run_test "Users in Ranger database" "docker exec ranger-db psql -U rangeradmin -d ranger -c 'SELECT COUNT(*) FROM x_user WHERE user_name LIKE '\''%.%'\''' 2>/dev/null | grep -q '5'"

echo ""
echo "3. Doris Tests"
echo "--------------"
run_test "Doris Frontend is running" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e 'SELECT 1'"
run_test "Doris Backend is running" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e 'SHOW BACKENDS' | grep -q 'true'"
run_test "Ranger plugin enabled" "docker exec doris-fe-01 cat /opt/apache-doris/fe/conf/fe.conf | grep -q 'access_controller_type = ranger-doris'"

echo ""
echo "4. User Sync Tests"
echo "------------------"
run_test "john.doe exists in Doris" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e \"SELECT COUNT(*) FROM mysql.user WHERE User='john.doe'\" | grep -q '1'"
run_test "jane.smith exists in Doris" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e \"SELECT COUNT(*) FROM mysql.user WHERE User='jane.smith'\" | grep -q '1'"
run_test "test.user exists in Doris" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e \"SELECT COUNT(*) FROM mysql.user WHERE User='test.user'\" | grep -q '1'"

echo ""
echo "5. Authentication Tests"
echo "-----------------------"
run_test "john.doe can login to Doris" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -ujohn.doe -ppassword123 -e 'SELECT 1'"
run_test "jane.smith can login to Doris" "docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -ujane.smith -ppassword123 -e 'SELECT 1'"

echo ""
echo "6. Integration Flow Test"
echo "------------------------"
echo "Creating new test user in LDAP..."

# Create a new user in LDAP
TIMESTAMP=$(date +%s)
NEW_USER="testuser${TIMESTAMP:(-4)}"

cat > /tmp/new-test-user.ldif <<EOF
dn: uid=$NEW_USER,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: $NEW_USER
sn: User
givenName: Test
cn: Test User $TIMESTAMP
displayName: Test User $TIMESTAMP
uidNumber: $TIMESTAMP
gidNumber: 10001
userPassword: TestPass123
gecos: Test User
loginShell: /bin/bash
homeDirectory: /home/$NEW_USER
mail: $NEW_USER@example.com
EOF

docker cp /tmp/new-test-user.ldif openldap:/tmp/
docker exec openldap ldapadd -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=com" -w admin123 -f /tmp/new-test-user.ldif > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Created user $NEW_USER in LDAP"

    # Run sync
    echo "Running LDAP-Doris sync..."
    ./scripts/ldap-doris-sync.sh once > /dev/null 2>&1

    # Check if user exists in Doris
    sleep 2
    if docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e "SELECT COUNT(*) FROM mysql.user WHERE User='$NEW_USER'" 2>/dev/null | grep -q '1'; then
        echo -e "${GREEN}✓${NC} User $NEW_USER successfully synced to Doris"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗${NC} User $NEW_USER NOT synced to Doris"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${RED}✗${NC} Failed to create test user in LDAP"
    ((TESTS_FAILED++))
fi

echo ""
echo "=========================================="
echo "Test Results Summary"
echo "=========================================="
echo -e "Tests Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ All tests passed! The integration is working correctly.${NC}"
else
    echo -e "\n${YELLOW}⚠ Some tests failed. Please check the configuration.${NC}"
fi

echo ""
echo "Current System Status:"
echo "----------------------"
echo "LDAP Users: $(docker exec openldap ldapsearch -x -H ldap://localhost:389 -D 'cn=admin,dc=example,dc=com' -w admin123 -b 'ou=users,dc=example,dc=com' '(objectClass=inetOrgPerson)' uid 2>/dev/null | grep -c '^uid:')"
echo "Ranger DB Users: $(docker exec ranger-db psql -U rangeradmin -d ranger -t -c 'SELECT COUNT(*) FROM x_user' 2>/dev/null | tr -d ' ')"
echo "Doris Users: $(docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e 'SELECT COUNT(*) FROM mysql.user' 2>/dev/null)"