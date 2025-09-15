#!/bin/bash

echo "Starting Ranger UserSync service..."

# Set environment variables for UserSync
export RANGER_USERSYNC_HOME=/opt/ranger/ranger-2.7.0-usersync

# Create necessary directories
mkdir -p ${RANGER_USERSYNC_HOME}/logs
mkdir -p ${RANGER_USERSYNC_HOME}/conf

# Copy configuration file if it doesn't exist
if [ -f "/opt/ranger/ranger-2.7.0-usersync/conf/ranger-usersync-site.xml" ]; then
    echo "Using provided ranger-usersync-site.xml configuration"
fi

# Wait for Ranger Admin to be ready
echo "Waiting for Ranger Admin to be available..."
until curl -f http://ranger:6080/ &>/dev/null; do
    echo "Ranger Admin is not ready yet. Sleeping for 10 seconds..."
    sleep 10
done
echo "Ranger Admin is ready!"

# Wait for LDAP to be ready
echo "Waiting for LDAP to be available..."
until nc -z openldap 389; do
    echo "LDAP is not ready yet. Sleeping for 5 seconds..."
    sleep 5
done
echo "LDAP is ready!"

# Set Java options
export JAVA_OPTS="-Xmx1024m"

# Start UserSync service
cd ${RANGER_USERSYNC_HOME}

# Run setup if needed
if [ ! -f "${RANGER_USERSYNC_HOME}/.setupDone" ]; then
    echo "Running UserSync setup..."
    ./setup.sh
    touch ${RANGER_USERSYNC_HOME}/.setupDone
fi

# Start the UserSync daemon
echo "Starting Ranger UserSync daemon..."
./ranger-usersync-services.sh start

# Keep container running and tail logs
echo "UserSync started. Tailing logs..."
tail -f ${RANGER_USERSYNC_HOME}/logs/*.log