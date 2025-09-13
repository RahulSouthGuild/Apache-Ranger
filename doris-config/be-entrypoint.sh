#!/bin/bash
# Custom entrypoint for Doris BE that handles config file properly

# Set ulimits
echo "Setting ulimits..."
ulimit -n 655350
ulimit -l unlimited
echo "Current ulimit -n: $(ulimit -n)"
echo "Current ulimit -l: $(ulimit -l)"

# If custom config exists, copy it to the config directory
if [ -f "/tmp/custom-be.conf" ]; then
    echo "Copying custom be.conf to /opt/apache-doris/be/conf/"
    cp /tmp/custom-be.conf /opt/apache-doris/be/conf/be.conf
    chmod 644 /opt/apache-doris/be/conf/be.conf
fi

# Set MySQL connection credentials for FE
export MYSQL_PWD=root

# Execute the original entrypoint
exec /docker-entrypoint.sh "$@"