#!/bin/bash

echo "Setting up LDAP authentication for Doris..."

# Wait for Doris FE to be ready
echo "Waiting for Doris FE to be ready..."
sleep 20

# Set LDAP admin password in Doris
echo "Setting LDAP admin password in Doris..."
docker exec -it doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e "SET LDAP_ADMIN_PASSWORD = PASSWORD('admin123');"

# Create roles in Doris that match LDAP groups
echo "Creating roles in Doris to match LDAP groups..."
docker exec -it doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e "
CREATE ROLE IF NOT EXISTS 'admin';
CREATE ROLE IF NOT EXISTS 'analyst';
CREATE ROLE IF NOT EXISTS 'user';
CREATE ROLE IF NOT EXISTS 'ldapDefaultRole';

-- Grant permissions to roles
GRANT ALL ON *.* TO ROLE 'admin';
GRANT SELECT ON *.* TO ROLE 'analyst';
GRANT SELECT ON *.* TO ROLE 'user';
GRANT SELECT ON information_schema.* TO ROLE 'ldapDefaultRole';

-- Create corresponding Ranger group mappings
CREATE ROLE IF NOT EXISTS 'admins';
CREATE ROLE IF NOT EXISTS 'data-analysts';
CREATE ROLE IF NOT EXISTS 'users';
CREATE ROLE IF NOT EXISTS 'ranger-admins';

GRANT ALL ON *.* TO ROLE 'ranger-admins';
GRANT ALL ON *.* TO ROLE 'admins';
GRANT SELECT, INSERT, UPDATE ON *.* TO ROLE 'data-analysts';
GRANT SELECT ON *.* TO ROLE 'users';
"

echo "LDAP setup for Doris completed!"