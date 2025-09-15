#!/bin/bash

# Script to clean up idle Doris connections

echo "Cleaning up idle Doris connections..."

# Get list of sleeping connection IDs and kill them
docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e "
SELECT CONCAT('KILL CONNECTION ', Id, ';')
FROM information_schema.processlist
WHERE Command = 'Sleep' AND Time > 10;" 2>/dev/null | \
docker exec -i doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot 2>/dev/null

# Check remaining connections
remaining=$(docker exec doris-fe-01 mysql -h127.0.0.1 -P9030 -uroot -N -e "SELECT COUNT(*) FROM information_schema.processlist;" 2>/dev/null)

echo "Remaining connections: $remaining"
echo "Cleanup complete!"