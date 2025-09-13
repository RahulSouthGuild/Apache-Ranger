#!/bin/bash

# Create Doris service instance in Ranger
echo "Creating Doris service instance in Ranger..."

curl -u admin:rangerR0cks! -X POST \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    http://172.20.0.20:6080/service/public/v2/api/service \
    -d '{
        "name": "doris-cluster",
        "displayName": "Doris Cluster Service",
        "description": "Apache Doris Service Instance",
        "type": "doris",
        "configs": {
            "username": "root",
            "password": "root",
            "jdbc.driver_class": "com.mysql.cj.jdbc.Driver",
            "jdbc.url": "jdbc:mysql://172.20.0.30:9030?useSSL=false"
        },
        "isEnabled": true
    }'

echo "Doris service instance creation complete"