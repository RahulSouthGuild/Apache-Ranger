#!/bin/bash
# Custom entrypoint for Doris FE that handles config file properly

# If custom config exists, copy it to the config directory
if [ -f "/tmp/custom-fe.conf" ]; then
    echo "Copying custom fe.conf to /opt/apache-doris/fe/conf/"
    cp /tmp/custom-fe.conf /opt/apache-doris/fe/conf/fe.conf
    chmod 644 /opt/apache-doris/fe/conf/fe.conf
fi

# Copy Ranger configuration files to multiple locations for classpath
if [ -f "/tmp/ranger-doris-security.xml" ]; then
    echo "Copying ranger-doris-security.xml to conf and lib directories"
    cp /tmp/ranger-doris-security.xml /opt/apache-doris/fe/conf/ranger-doris-security.xml
    cp /tmp/ranger-doris-security.xml /opt/apache-doris/fe/lib/ranger-doris-security.xml
    chmod 644 /opt/apache-doris/fe/conf/ranger-doris-security.xml
    chmod 644 /opt/apache-doris/fe/lib/ranger-doris-security.xml
fi

if [ -f "/tmp/ranger-doris-audit.xml" ]; then
    echo "Copying ranger-doris-audit.xml to conf and lib directories"
    cp /tmp/ranger-doris-audit.xml /opt/apache-doris/fe/conf/ranger-doris-audit.xml
    cp /tmp/ranger-doris-audit.xml /opt/apache-doris/fe/lib/ranger-doris-audit.xml
    chmod 644 /opt/apache-doris/fe/conf/ranger-doris-audit.xml
    chmod 644 /opt/apache-doris/fe/lib/ranger-doris-audit.xml
fi

if [ -f "/tmp/log4j.properties" ]; then
    echo "Copying log4j.properties to conf directory"
    cp /tmp/log4j.properties /opt/apache-doris/fe/conf/log4j.properties
    chmod 644 /opt/apache-doris/fe/conf/log4j.properties
fi

# Copy LDAP configuration if it exists
if [ -f "/tmp/ldap.conf" ]; then
    echo "Copying ldap.conf to conf directory"
    cp /tmp/ldap.conf /opt/apache-doris/fe/conf/ldap.conf
    chmod 644 /opt/apache-doris/fe/conf/ldap.conf
fi

# Copy Ranger plugin JARs if they exist
if [ -f "/tmp/ranger-doris-plugin-3.0.0-SNAPSHOT.jar" ]; then
    echo "Copying Ranger Doris plugin JAR to lib directory"
    cp /tmp/ranger-doris-plugin-3.0.0-SNAPSHOT.jar /opt/apache-doris/fe/lib/
    chmod 644 /opt/apache-doris/fe/lib/ranger-doris-plugin-3.0.0-SNAPSHOT.jar
fi

if [ -f "/tmp/mysql-connector-java-8.0.25.jar" ]; then
    echo "Copying MySQL connector JAR to lib directory"
    cp /tmp/mysql-connector-java-8.0.25.jar /opt/apache-doris/fe/lib/
    chmod 644 /opt/apache-doris/fe/lib/mysql-connector-java-8.0.25.jar
fi

# Create Ranger cache directory
mkdir -p /opt/apache-doris/fe/ranger-cache
chmod 755 /opt/apache-doris/fe/ranger-cache

# Execute the original entrypoint
exec /docker-entrypoint.sh "$@"