# Sync Timing Configuration

## Current Sync Intervals (Updated)

| Service | Old Interval | New Interval | Where Users Appear |
|---------|-------------|--------------|-------------------|
| **LDAP → Ranger** | 5 minutes (300 sec) | **30 seconds** | Ranger Database |
| **LDAP → Doris** | 60 seconds | **30 seconds** | Doris Users |

## What This Means

When you create a new user in LDAP:
- **After 30 seconds**: User appears in both Ranger and Doris
- **Previously**: Had to wait 5 minutes for Ranger, 1 minute for Doris

## Files Changed

### 1. Ranger UserSync (`docker-compose.yml`)
```yaml
# Line 180 - Changed from:
sleep 300  # 5 minutes

# To:
sleep 30   # 30 seconds
```

### 2. Doris Sync Script (`scripts/ldap-doris-sync.sh`)
```bash
# Line 21 - Changed from:
SYNC_INTERVAL=${SYNC_INTERVAL:-60}

# To:
SYNC_INTERVAL=${SYNC_INTERVAL:-30}
```

### 3. Doris Sync Service (`docker-compose-ldap-doris-sync.yml`)
```yaml
# Line 10 - Changed from:
SYNC_INTERVAL: 60

# To:
SYNC_INTERVAL: 30
```

## How to Apply Changes

### Option 1: Restart Individual Services
```bash
# Restart Ranger UserSync
docker-compose restart ranger-usersync

# Restart Doris sync (if running as service)
docker-compose -f docker-compose-ldap-doris-sync.yml restart ldap-doris-sync
```

### Option 2: Restart Everything
```bash
docker-compose down
docker-compose up -d
```

## Testing the New Timing

1. Create a new test user in LDAP:
```bash
# Via phpLDAPadmin UI at http://localhost:6081
# OR via command line
```

2. Wait 30 seconds

3. Check if user appears:
```bash
# Check in Ranger database
docker exec ranger-db psql -U rangeradmin -d ranger -c \
  "SELECT user_name FROM x_user WHERE user_name='newuser';"

# Check in Doris
docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -e \
  "SELECT User FROM mysql.user WHERE User='newuser';"
```

## Performance Considerations

### Pros of 30-Second Sync:
- ✅ Faster user availability
- ✅ Better user experience
- ✅ Quick testing and development

### Cons of 30-Second Sync:
- ⚠️ More frequent API calls
- ⚠️ Higher CPU usage
- ⚠️ More network traffic
- ⚠️ More log entries

### Recommended Settings:

| Environment | LDAP→Ranger | LDAP→Doris | Reason |
|------------|------------|------------|---------|
| **Development** | 30 seconds | 30 seconds | Fast feedback |
| **Testing** | 1 minute | 1 minute | Balance |
| **Production** | 5 minutes | 5 minutes | Less overhead |

## Customizing Sync Intervals

You can set any interval you want:

### For Ranger UserSync:
Edit `docker-compose.yml` line 180:
```bash
sleep 30   # Change 30 to any number of seconds
```

### For Doris Sync:
Set environment variable:
```bash
SYNC_INTERVAL=15 ./scripts/ldap-doris-sync.sh continuous
```

Or edit the default in `scripts/ldap-doris-sync.sh`:
```bash
SYNC_INTERVAL=${SYNC_INTERVAL:-30}  # Change 30 to your preference
```

## Monitoring Sync Activity

### View Ranger UserSync logs:
```bash
docker logs ranger-usersync --tail 20
```

### View Doris sync logs:
```bash
tail -f /tmp/ldap-doris-sync.log
```

### Check last sync time:
```bash
grep "sync completed" /tmp/ldap-doris-sync.log | tail -1
```

## Important Notes

1. **Don't set too low**: Less than 10 seconds may cause issues
2. **Consider LDAP load**: Frequent queries can impact LDAP performance
3. **Database connections**: Each sync creates new database connections
4. **Network stability**: Ensure network is stable for frequent syncs

The sync is now set to **30 seconds** for both Ranger and Doris!