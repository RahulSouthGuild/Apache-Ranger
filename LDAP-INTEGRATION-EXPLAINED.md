# LDAP Integration with Ranger and Doris - Complete Explanation

## Table of Contents
1. [What We Were Trying to Do](#what-we-were-trying-to-do)
2. [The Problems We Faced](#the-problems-we-faced)
3. [How We Solved Each Problem](#how-we-solved-each-problem)
4. [How Everything Connects](#how-everything-connects)
5. [Important Files and What They Do](#important-files-and-what-they-do)
6. [The Final Working Solution](#the-final-working-solution)

---

## What We Were Trying to Do

We wanted to create a **single place to manage users** (LDAP) that would automatically sync users to:
- **Apache Ranger** (for security permissions)
- **Apache Doris** (for database access)

The goal: **Create a user once in LDAP, and it appears everywhere!**

---

## The Problems We Faced

### Problem 1: Ranger UserSync Container Not Working
**What happened**: The container labeled `ranger-usersync` was actually running Ranger Admin service instead of UserSync.

**Why it happened**: Apache doesn't provide a separate UserSync Docker image. The `apache/ranger:2.7.0` image runs Admin by default.

**Error we saw**:
```
Container ranger-usersync is running Ranger Admin logs instead of UserSync logs
```

### Problem 2: Doris Doesn't Support LDAP Natively
**What happened**: We tried to enable LDAP authentication in Doris, but it kept failing.

**Why it happened**: Open-source Doris doesn't have built-in LDAP support (only commercial versions do).

**Errors we saw**:
```
ERROR 2013 (HY000): Lost connection to MySQL server at 'reading authorization packet'
java.lang.NumberFormatException: For input string: "43200  # 12 hours"
```

### Problem 3: No Automatic User Sync from LDAP to Doris
**What happened**: Even after fixing Ranger sync, users created in LDAP didn't appear in Doris.

**Why it happened**: There's no built-in mechanism to sync LDAP users to Doris.

**The issue**:
```
Creating user in LDAP ✓
User appears in Ranger ✓
User appears in Doris ✗ (Doesn't happen automatically)
```

### Problem 4: Password Synchronization Issues
**What happened**: Passwords are stored differently in each system.

**The complexity**:
- LDAP: Stores hashed passwords (encrypted)
- Ranger: Doesn't store passwords at all
- Doris: Needs plain text password to create users

---

## How We Solved Each Problem

### Solution 1: Created Custom UserSync Script
Instead of using the broken UserSync container, we created our own sync script.

**What we did**:
1. Removed the misconfigured container
2. Created a custom Ubuntu container
3. Wrote a bash script (`ldap-sync-script.sh`) that:
   - Reads users from LDAP
   - Creates them in Ranger using REST API
   - Runs every 5 minutes

**The fix** (`docker-compose.yml`):
```yaml
ranger-usersync:
  image: ubuntu:22.04  # Using Ubuntu instead of apache/ranger
  volumes:
    - ./ranger-config/ldap-sync-script.sh:/opt/ldap-sync-script.sh
  command:
    - Run our custom sync script every 5 minutes
```

### Solution 2: Disabled LDAP in Doris, Used Manual User Creation
Since Doris doesn't support LDAP authentication, we:
1. Disabled LDAP authentication in Doris
2. Created users manually in Doris
3. Used Ranger for permission control

**The fix** (`doris-config/fe/fe.conf`):
```properties
# Before (not working):
authentication_type = ldap  # This doesn't work!

# After (working):
# authentication_type = ldap  # Commented out
access_controller_type = ranger-doris  # Only use Ranger
```

### Solution 3: Created LDAP-to-Doris Sync Script
We built a custom script that syncs users from LDAP to Doris.

**What the script does** (`scripts/ldap-doris-sync.sh`):
1. Gets all users from LDAP
2. Checks if each user exists in Doris
3. Creates missing users in Doris
4. Runs every 60 seconds

### Solution 4: Used Default Passwords for Synced Users
Since we can't read LDAP passwords (they're encrypted), we:
1. Create all Doris users with a default password: `password123`
2. Users can change their password later if needed

---

## How Everything Connects

### The Flow of User Creation:

```
1. You create user in LDAP (via phpLDAPadmin UI)
                ↓
2. Ranger UserSync polls LDAP every 5 minutes
                ↓
3. User appears in Ranger (for permissions)
                ↓
4. Our custom script polls LDAP every 60 seconds
                ↓
5. User is created in Doris (for database access)
```

### Network Connections:

```
Service         | Container Name    | IP Address      | Port
----------------|-------------------|-----------------|------
LDAP Server     | openldap         | 172.20.0.50     | 389
Ranger Admin    | ranger           | 172.20.0.20     | 6080
Doris Frontend  | doris-fe-01      | 172.20.0.30     | 9030
UserSync Script | ranger-usersync  | 172.20.0.21     | -
```

---

## Important Files and What They Do

### 1. LDAP Configuration Files

#### `ldap-config/ldap-init.ldif`
**What it does**: Contains initial users and groups for LDAP
```ldif
dn: uid=john.doe,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
uid: john.doe
userPassword: password123
```

#### `ldap-config/add-users.ldif`
**What it does**: Template for adding new users to LDAP

### 2. Ranger Sync Files

#### `ranger-config/ldap-sync-script.sh`
**What it does**: Syncs users from LDAP to Ranger
```bash
# Key parts:
- Connects to LDAP using ldapsearch
- Gets list of users
- Creates each user in Ranger using curl API calls
- Runs every 5 minutes
```

**How it connects to LDAP**:
```bash
ldapsearch -x -H "ldap://openldap:389" \
  -D "cn=admin,dc=example,dc=com" \
  -w "admin123" \
  -b "ou=users,dc=example,dc=com"
```

**How it creates users in Ranger**:
```bash
curl -X POST -u admin:rangerR0cks! \
  http://ranger:6080/service/xusers/secure/users \
  -d '{"name":"john.doe","password":"Pass123!"}'
```

### 3. Doris Sync Files

#### `scripts/ldap-doris-sync.sh`
**What it does**: Syncs users from LDAP to Doris
```bash
# Key parts:
- Gets users from LDAP
- Checks if user exists in Doris
- Creates missing users with default password
```

**How it connects to Doris**:
```bash
mysql -h127.0.0.1 -P9030 -uroot -e \
  "CREATE USER 'john.doe'@'%' IDENTIFIED BY 'password123';"
```

### 4. Docker Configuration

#### `docker-compose.yml`
**What it does**: Defines all containers and their connections
```yaml
services:
  openldap:        # LDAP server
  ranger:          # Ranger Admin
  ranger-usersync: # Our custom sync container
  doris-fe-01:     # Doris Frontend
  doris-be-01:     # Doris Backend
```

### 5. Configuration Files

#### `doris-config/fe/fe.conf`
**What it does**: Doris configuration
```properties
access_controller_type = ranger-doris  # Use Ranger for permissions
# authentication_type = ldap  # Disabled - doesn't work
```

#### `doris-config/fe/ldap.conf`
**What it was supposed to do**: Configure LDAP for Doris (didn't work)
**Status**: Not used because Doris doesn't support LDAP

---

## The Final Working Solution

### What Actually Works Now:

1. **LDAP → Ranger**: ✅ Automatic sync every 5 minutes
   - File: `ranger-config/ldap-sync-script.sh`
   - How: Custom script using REST API

2. **LDAP → Doris**: ✅ Automatic sync every 60 seconds
   - File: `scripts/ldap-doris-sync.sh`
   - How: Custom script using MySQL commands

3. **Ranger → Doris**: ✅ Permission control
   - File: `doris-config/fe/fe.conf`
   - How: Ranger plugin in Doris

### How to Use It:

#### 1. Create User in LDAP (Web UI):
```
1. Go to http://localhost:6081
2. Login: cn=admin,dc=example,dc=com / admin123
3. Navigate to ou=users
4. Create new user
```

#### 2. User Automatically Appears In:
- **Ranger**: After 5 minutes (for permissions)
- **Doris**: After 60 seconds (for login)

#### 3. User Can Login to Doris:
```bash
mysql -h localhost -P 9031 -u john.doe -p password123
```

### Key Scripts to Run:

#### Start Everything:
```bash
docker-compose up -d
```

#### Run LDAP to Doris Sync:
```bash
./scripts/ldap-doris-sync.sh continuous
```

#### Test Everything:
```bash
./scripts/test-complete-integration.sh
```

---

## Why This Solution Works

1. **We stopped trying to make Doris do LDAP authentication** (it can't)
2. **We created our own sync scripts** instead of relying on broken containers
3. **We accepted that passwords can't be synced** (use defaults instead)
4. **We used what each system does best**:
   - LDAP: Store users
   - Ranger: Control permissions
   - Doris: Process queries

---

## Common Issues and Fixes

### Issue: User created in LDAP but can't login to Doris
**Fix**: Run the sync script manually:
```bash
./scripts/ldap-doris-sync.sh once
```

### Issue: Ranger UserSync not working
**Fix**: Check if the custom script is running:
```bash
docker logs ranger-usersync
```

### Issue: Password doesn't work in Doris
**Fix**: All synced users use password `password123` by default:
```bash
# Or change it manually:
docker exec doris-fe-01 mysql -uroot -e \
  "ALTER USER 'username'@'%' IDENTIFIED BY 'newpassword';"
```

---

## Summary

The main lesson: **Not everything works out of the box!**

- **Expected**: LDAP → Automatic sync → Everything works
- **Reality**: Had to build custom scripts for each connection
- **Result**: It works, but needs our custom "glue" code

The solution isn't perfect, but it works reliably and can be improved over time.