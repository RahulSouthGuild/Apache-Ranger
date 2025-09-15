# LDAP Integration Guide for Apache Ranger and Doris

## Overview
This guide documents the complete LDAP integration setup for user synchronization between LDAP, Apache Ranger, and Apache Doris.

## Architecture

```
┌─────────────┐
│    LDAP     │ ← Central User Repository
│  (OpenLDAP) │
└──────┬──────┘
       │
       ├──────────────┬──────────────┐
       ↓              ↓              ↓
┌──────────────┐ ┌──────────┐ ┌─────────────┐
│Ranger UserSync│ │   Doris  │ │phpLDAPadmin │
│   (Sync)      │ │   (Auth) │ │   (Admin)   │
└──────────────┘ └──────────┘ └─────────────┘
```

## Services and Access URLs

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| phpLDAPadmin | http://localhost:6081 | cn=admin,dc=example,dc=com / admin123 |
| Ranger Admin | http://localhost:6080 | admin / rangerR0cks! |
| Doris FE | http://localhost:8031 | root / (no password) |
| LDAP Server | ldap://localhost:389 | cn=admin,dc=example,dc=com / admin123 |

## LDAP Users and Groups

### Test Users
- **john.doe** / password123 (Group: admins)
- **jane.smith** / password123 (Group: users, data-analysts)
- **admin.user** / admin123 (Group: admins, ranger-admins)
- **data.analyst** / password123 (Group: users, data-analysts)

### Groups
- **admins** - System Administrators
- **users** - Regular Users
- **data-analysts** - Data Analysts
- **ranger-admins** - Ranger Administrators

## Key Features

### 1. Password Policy Handling
- **Challenge**: Ranger requires complex passwords (8+ chars, uppercase, lowercase, numbers)
- **Solution**: LDAP enforces password policies centrally
- **Doris**: Accepts LDAP passwords regardless of complexity

### 2. User Synchronization
- **Ranger UserSync**: Pulls users/groups from LDAP every 5 minutes
- **Doris**: Creates temporary users on successful LDAP authentication
- **Group Mapping**: LDAP groups automatically map to Ranger/Doris roles

### 3. Edge Cases Handled
- User exists in LDAP but not in target systems → Automatic provisioning
- Group membership changes → Synced within 5 minutes
- Service downtime → Retry mechanisms in place
- Password changes → Immediate effect in LDAP, propagated to all systems

## Configuration Files

### 1. LDAP Configuration (`ldap-config/ldap-init.ldif`)
Contains initial LDAP structure, users, and groups.

### 2. Doris LDAP (`doris-config/fe/ldap.conf`)
```properties
ldap_host = openldap
ldap_port = 389
ldap_user_filter = (&(objectClass=inetOrgPerson)(uid={login}))
ldap_group_filter = (&(objectClass=posixGroup)(memberUid={user}))
```

### 3. Ranger UserSync (`ranger-config/ranger-usersync-site.xml`)
```xml
<property>
    <name>ranger.usersync.source.impl.class</name>
    <value>org.apache.ranger.ldapusersync.process.LdapUserGroupBuilder</value>
</property>
```

## Testing the Integration

### 1. Quick Test
```bash
./scripts/test-ldap-integration.sh
```

### 2. Manual Authentication Test
```bash
# Test Doris LDAP authentication
export LIBMYSQL_ENABLE_CLEARTEXT_PLUGIN=1
mysql -h127.0.0.1 -P9031 -ujohn.doe -ppassword123 -e "SELECT CURRENT_USER();"

# Check Ranger users
curl -u admin:rangerR0cks! http://localhost:6080/service/xusers/users
```

### 3. Add New LDAP User
```bash
./scripts/add-ldap-user.sh testuser Test User TestPass123! data-analysts
```

## Security Considerations

### Current Implementation
1. **LDAP**: Uses simple bind authentication
2. **Doris**: Plaintext password transmission (security concern)
3. **Ranger**: Secure password handling

### Recommended Improvements
1. Enable LDAPS (LDAP over SSL) for encrypted connections
2. Use STARTTLS for opportunistic encryption
3. Implement Kerberos for stronger authentication
4. Use certificate-based authentication where possible

## Troubleshooting

### LDAP Connection Issues
```bash
# Test LDAP connectivity
docker exec openldap ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=com" -w admin123 -b "dc=example,dc=com"
```

### Ranger UserSync Not Working
```bash
# Check UserSync logs
docker logs ranger-usersync

# Verify UserSync configuration
docker exec ranger-usersync cat /opt/ranger/ranger-2.7.0-usersync/conf/ranger-usersync-site.xml
```

### Doris LDAP Authentication Fails
```bash
# Check Doris FE logs
docker logs doris-fe-01 | grep -i ldap

# Verify LDAP configuration
docker exec doris-fe-01 cat /opt/apache-doris/fe/conf/ldap.conf
```

## Maintenance

### Restart Services
```bash
# Restart LDAP
docker-compose restart openldap

# Restart Ranger UserSync
docker-compose restart ranger-usersync

# Restart Doris FE
docker-compose restart doris-fe-01
```

### Clear LDAP Cache in Doris
```sql
-- Connect as root
mysql -h127.0.0.1 -P9030 -uroot
-- Refresh LDAP cache
REFRESH LDAP;
```

## Known Limitations

1. **Password Synchronization**: Passwords are hashed, cannot sync between systems
2. **Doris Security**: Uses plaintext LDAP authentication (not encrypted)
3. **Sync Delay**: 5-minute delay for user/group synchronization to Ranger
4. **Cache**: 12-hour cache in Doris for LDAP users

## Future Enhancements

1. Implement LDAPS for secure connections
2. Add password policy enforcement via ppolicy overlay
3. Implement automated backup of LDAP data
4. Add monitoring and alerting for sync failures
5. Implement single sign-on (SSO) using SAML or OAuth