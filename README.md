# Apache Doris + Apache Ranger Integration

This repository contains a complete Docker Compose setup for running Apache Doris with Apache Ranger for centralized security management and access control.

## Architecture Overview

- **Apache Ranger 2.7.0**: Centralized security administration for Doris (using official Apache images)
- **Apache Doris 3.0.5**: High-performance analytical database
- **PostgreSQL**: Database backend for Ranger (using apache/ranger-db image)
- **Apache Solr**: Audit log storage (using apache/ranger-solr image)
- **Zookeeper**: Coordination service (using apache/ranger-zk image)

## Prerequisites

- Docker Engine 20.10.5+
- Docker Compose 1.28.5+
- At least 8GB RAM allocated to Docker
- 20GB+ free disk space

## Directory Structure

```
.
├── docker-compose.yml          # Main orchestration file
├── .env                        # Environment variables
├── doris-config/
│   ├── fe/                     # Frontend configuration
│   │   ├── fe.conf
│   │   ├── ranger-doris-security.xml
│   │   └── ranger-doris-audit.xml
│   └── be/                     # Backend configuration
│       └── be.conf
└── ranger-config/
    ├── postgres-init.sql       # Database initialization
    ├── ranger-admin/           # Admin configuration
    ├── ranger-usersync/        # User sync configuration
    └── ranger-tagsync/         # Tag sync configuration
```

## Quick Start

### 1. Clone and Navigate

```bash
cd /home/rahul/RahulSouthGuild/Apache-Ranger
```

### 2. Start All Services

Choose one of the following methods:

#### Method 1: Using Docker Compose (Recommended)
```bash
# Start all services
docker-compose up -d

# Or start with logs
docker-compose up
```

#### Method 2: Using Official Ranger Script
```bash
# Use the start script based on official Ranger documentation
./start-ranger.sh
```

#### Method 3: Using Simplified Docker Compose
```bash
# Use the simplified version
docker-compose -f docker-compose-simple.yml up -d
```

### 3. Wait for Services to Initialize

Services will be available at:
- **Ranger Admin UI**: http://localhost:6080 (admin/rangerR0cks!)
- **Doris FE UI**: http://localhost:8030
- **Doris Query Port**: localhost:9030 (MySQL protocol)
- **Solr Admin**: http://localhost:8983
- **PostgreSQL**: localhost:5433 (mapped from container's 5432)

### 4. Verify Services

```bash
# Check all services are running
docker-compose ps

# Check Ranger Admin health
curl http://localhost:6080/

# Check Doris FE health
curl http://localhost:8030/api/bootstrap

# Check Doris BE health
curl http://localhost:8040/api/health
```

## Configuration

### Doris Configuration

#### Frontend (FE) Configuration
- Config file: `doris-config/fe/fe.conf`
- Ranger integration: `doris-config/fe/ranger-doris-security.xml`
- Audit configuration: `doris-config/fe/ranger-doris-audit.xml`

#### Backend (BE) Configuration
- Config file: `doris-config/be/be.conf`

### Ranger Configuration

#### Setting up Doris Service in Ranger

1. Access Ranger Admin UI at http://localhost:6080
2. Login with admin/rangerR0cks!
3. Click on "+" to add a new service
4. Select "Doris" as service type
5. Configure with:
   - Service Name: `doris`
   - Username: `admin`
   - Password: `admin`
   - JDBC URL: `jdbc:mysql://doris-fe:9030/`
   - JDBC Driver: `com.mysql.cj.jdbc.Driver`

### Network Configuration

All services use the same Docker network (`doris-ranger-network`) with subnet `172.20.0.0/16`:

- PostgreSQL: 172.20.0.10
- Solr: 172.20.0.11
- Zookeeper: 172.20.0.12
- Ranger Admin: 172.20.0.20
- Ranger UserSync: 172.20.0.21
- Ranger TagSync: 172.20.0.22
- Doris FE: 172.20.0.30
- Doris BE: 172.20.0.31

## Common Operations

### Viewing Logs

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f ranger-admin
docker-compose logs -f doris-fe
docker-compose logs -f doris-be
```

### Scaling Backend Nodes

To add more Doris BE nodes, uncomment the `doris-be-2` section in docker-compose.yml or add:

```yaml
doris-be-2:
  image: apache/doris:2.1.0-be
  container_name: doris-be-2
  # ... (configuration similar to doris-be)
```

### Connecting to Doris

```bash
# Using MySQL client
mysql -h127.0.0.1 -P9030 -uroot

# Using Docker exec
docker exec -it doris-fe mysql -uroot -P9030 -h127.0.0.1
```

### Managing Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (CAUTION: Deletes all data)
docker-compose down -v

# Restart a specific service
docker-compose restart doris-fe

# Scale backend nodes
docker-compose up -d --scale doris-be=3
```

## Ranger Policy Management

### Creating Policies

1. Login to Ranger Admin UI
2. Click on the "doris" service
3. Click "Add New Policy"
4. Configure:
   - Policy Name: Descriptive name
   - Database: Target database(s)
   - Table: Target table(s)
   - Column: Target column(s)
   - Select User/Group and permissions

### Policy Types

- **Access Policies**: Control who can access what resources
- **Masking Policies**: Define data masking rules for sensitive columns
- **Row Filter Policies**: Implement row-level security

## Troubleshooting

### Service Won't Start

```bash
# Check logs
docker-compose logs [service-name]

# Verify port availability
netstat -tulpn | grep -E '(6080|8030|9030|5432)'

# Check Docker resources
docker system df
docker stats
```

### Ranger Connection Issues

1. Verify PostgreSQL is running: `docker-compose ps postgres`
2. Check Ranger Admin logs: `docker-compose logs ranger-admin`
3. Ensure database is initialized: Check postgres logs

### Doris Connection Issues

1. Verify FE is running: `curl http://localhost:8030/api/bootstrap`
2. Check BE registration: Access FE UI and check System > Backends
3. Review FE logs: `docker-compose logs doris-fe`

### Common Issues

1. **Memory Issues**: Increase Docker memory allocation
2. **Port Conflicts**: Change ports in docker-compose.yml and .env
3. **Network Issues**: Restart Docker daemon
4. **Permission Issues**: Ensure config files have proper permissions

## Performance Tuning

### Doris Tuning

- Adjust memory settings in `fe.conf` and `be.conf`
- Configure cache sizes based on workload
- Optimize compaction settings

### Ranger Tuning

- Adjust policy cache settings in `ranger-doris-security.xml`
- Configure audit batch sizes for better performance
- Tune thread pool sizes

## Security Considerations

1. **Change Default Passwords**: Update all default passwords in production
2. **Enable SSL/TLS**: Configure SSL for all services in production
3. **Network Security**: Use proper firewall rules
4. **Audit Logs**: Regularly review audit logs in Solr

## Backup and Recovery

### Backup

```bash
# Backup Ranger policies
docker exec ranger-admin /opt/ranger/backup-policies.sh

# Backup Doris metadata
docker exec doris-fe /opt/apache-doris/bin/backup.sh

# Backup PostgreSQL
docker exec postgres pg_dump -U ranger ranger > ranger-backup.sql
```

### Recovery

```bash
# Restore PostgreSQL
docker exec -i postgres psql -U ranger ranger < ranger-backup.sql

# Restore Doris metadata
docker exec doris-fe /opt/apache-doris/bin/restore.sh
```

## Monitoring

### Health Checks

All services include health checks that can be monitored:

```bash
# Check health status
docker inspect [container-name] | grep -A 10 Health
```

### Metrics

- Doris metrics: http://localhost:8030/metrics
- Solr metrics: http://localhost:8983/solr/admin/metrics

## Support and Documentation

- [Apache Doris Documentation](https://doris.apache.org/docs/)
- [Apache Ranger Documentation](https://ranger.apache.org/)
- [Doris-Ranger Integration Guide](https://doris.apache.org/docs/admin-manual/auth/ranger/)

## License

This setup is provided as-is for development and testing purposes. Ensure you comply with Apache License 2.0 for both Apache Doris and Apache Ranger.