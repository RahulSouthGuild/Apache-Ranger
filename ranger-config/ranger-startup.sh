#!/bin/bash

# Start Ranger in background
/home/ranger/scripts/ranger.sh &
RANGER_PID=$!

# Wait for Ranger to be ready
echo "Waiting for Ranger to be ready..."
max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if curl -f -s http://localhost:6080/ > /dev/null 2>&1; then
        echo "Ranger is ready!"
        break
    fi
    echo "Waiting for Ranger... (attempt $((attempt+1))/$max_attempts)"
    sleep 5
    attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "Ranger failed to start within timeout"
    exit 1
fi

# Wait a bit more to ensure Ranger is fully initialized
sleep 10

# Check if Doris service definition already exists
echo "Checking if Doris service definition already exists..."
EXISTING_DORIS=$(curl -s -u admin:rangerR0cks! \
    -H "Accept: application/json" \
    http://localhost:6080/service/plugins/definitions/name/doris 2>/dev/null | grep -c '"name":"doris"' || true)

if [ "$EXISTING_DORIS" -eq "0" ] 2>/dev/null || [ -z "$EXISTING_DORIS" ]; then
    echo "Registering Doris service definition..."
    RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -u admin:rangerR0cks! -X POST \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        http://localhost:6080/service/plugins/definitions \
        -d@/opt/ranger-config/ranger-servicedef-doris.json)

    HTTP_STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS" | cut -d: -f2)
    BODY=$(echo "$RESPONSE" | sed -n '1,/HTTP_STATUS/p' | sed '$d')

    if [ "$HTTP_STATUS" -eq "200" ] || [ "$HTTP_STATUS" -eq "201" ]; then
        echo "Doris service definition registered successfully!"
        echo "Response: $(echo "$BODY" | grep -o '"name":"[^"]*"' | head -1)"
    else
        echo "Failed to register Doris service definition. HTTP Status: $HTTP_STATUS"
        echo "Response: $BODY"
    fi
else
    echo "Doris service definition already exists, skipping registration"
fi

# Keep the container running by waiting for the Ranger process
wait $RANGER_PID