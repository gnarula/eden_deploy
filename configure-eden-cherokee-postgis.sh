#!/bin/bash

# Script to configure an Eden server
# - assumes that install-eden-cherokee-postgis.sh has been run

# Utility function to generate a random string
randpw(){ < /dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-16};echo;}

function ConfigureQuestion {
    unset password
    unset domain
    unset hostname
    unset sitename
    echo -e "Eden Configuration\n"
    echo -e "Using domain: $1"
    domain=$1

    echo -e "Using hostname: $2"
    hostname=$2
    sitename=$hostname".$domain"

    echo -e "Using template: $3"
    template=$3
    if [ -z ${template} ]
        then
        echo -e "Using default template "
        template='default'
    fi

    password=$( randpw )
    echo -e "Take note of this Password, this will be used in configuring Postgresql"
    echo ${password}

    echo "Now reconfiguring system to use the hostname: $hostname"

    cd /etc
    filename="hosts"
    sed -i "s|localhost.localdomain localhost|$sitename $hostname localhost.localdomain localhost|" $filename

    cd /etc
    filename="hostname"
    echo $hostname > $filename

    cd /etc
    filename="mailname"
    echo $sitename >  $filename
}

function UpdateEden {
    echo -e "Updating Eden"
    # Update system (in case run at a much later time than the install script)
    apt-get update
    apt-get upgrade -y
    cd ~web2py
    git pull
    cd ~web2py/applications/eden
    git pull
}

function ConfigEmail {
    # -----------------------------------------------------------------------------
    # Email
    # -----------------------------------------------------------------------------
    echo configure for Internet mail delivery
    echo accept all other defaults
    dpkg-reconfigure -f noninteractive exim4-config
}

function ConfigTemplates {
    # -----------------------------------------------------------------------------
    # Sahana Eden
    # -----------------------------------------------------------------------------
    echo "Setting up Sahana"

    # Copy Templates
    cp ~web2py/applications/eden/private/templates/000_config.py ~web2py/applications/eden/models

    sed -i "s|settings.base.template = \"default\"|settings.base.template = \"$template\"|" ~web2py/applications/eden/models/000_config.py
    sed -i 's|EDITING_CONFIG_FILE = False|EDITING_CONFIG_FILE = True|' ~web2py/applications/eden/models/000_config.py
    sed -i "s|akeytochange|$sitename$password|" ~web2py/applications/eden/models/000_config.py
    sed -i "s|#settings.base.public_url = \"http://127.0.0.1:8000\"|settings.base.public_url = \"http://$sitename\"|" ~web2py/applications/eden/models/000_config.py
    sed -i 's|#settings.base.cdn = True|settings.base.cdn = True|' ~web2py/applications/eden/models/000_config.py
}

function ConfigurePostgreSQL {
    # PostgreSQL
    echo "CREATE USER sahana WITH PASSWORD '$password';" > /tmp/pgpass.sql
    su -c - postgres "psql -q -d template1 -f /tmp/pgpass.sql"
    rm -f /tmp/pgpass.sql
    su -c - postgres "createdb -O sahana -E UTF8 sahana -T template0"
    #su -c - postgres "createlang plpgsql -d sahana"
    echo "Adding GIS"
    # PostGIS
    PostGIS=$( dpkg-query -L postgresql-9.3-postgis-scripts | grep -P "postgis--\d+.\d+.\d+.sql" )
    echo "Found ${PostGis} "
    su -c - postgres "psql -q -d sahana -f ${PostGIS}"
    su -c - postgres "psql -q -d sahana -c 'grant all on geometry_columns to sahana;'"
    su -c - postgres "psql -q -d sahana -c 'grant all on spatial_ref_sys to sahana;'"
}

function ConfigDatabase {
    # Configure Database
    echo -e "Making changes to 000_config.py"
    sed -i 's|#settings.database.db_type = "postgres"|settings.database.db_type = "postgres"|' ~web2py/applications/eden/models/000_config.py
    sed -i "s|#settings.database.password = \"password\"|settings.database.password = \"$password\"|" ~web2py/applications/eden/models/000_config.py
    sed -i 's|#settings.gis.spatialdb = True|settings.gis.spatialdb = True|' ~web2py/applications/eden/models/000_config.py
    echo -e  "Creating Tables and popluate with base data"
    # Create the Tables & Populate with base data
    sed -i 's|settings.base.migrate = False|settings.base.migrate = True|' ~web2py/applications/eden/models/000_config.py
    cd ~web2py
    sudo -H -u web2py python web2py.py -S eden -M -R applications/eden/static/scripts/tools/noop.py
}

function ConfigProduciton {
    # Configure for Production
    sed -i 's|#settings.base.prepopulate = 0|settings.base.prepopulate = 0|' ~web2py/applications/eden/models/000_config.py
    sed -i 's|settings.base.migrate = True|settings.base.migrate = False|' ~web2py/applications/eden/models/000_config.py
    cd ~web2py
    sudo -H -u web2py python web2py.py -S eden -M -R applications/eden/static/scripts/tools/compile.py
}

function ConfigBackup {
    # Schedule backups for 02:01 daily
    echo "1 2   * * * * root    /usr/local/bin/backup" >> "/etc/crontab"

    #read -p "Press any key to Reboot..."
    echo "Now rebooting.."
}

function Init {
    # Check if the script has root permissions if not exit
    if [ "$(id -u)" != "0" ]; then
        echo -e  "This script must be run as root"
        echo -e  "run: sudo $0"
        exit 1
    fi

    if [ $# -ne ]

    ConfigureQuestion $1 $2 $3 $4
    UpdateEden
    ConfigEmail
    ConfigTemplates
    ConfigurePostgreSQL
    ConfigDatabase
    ConfigProduciton
    ConfigBackup

    echo "Done Configuring"
}

if [ $# -ne 3 ]
then
    echo "Incorrect number of arguments"
    exit 1
fi

Init $1 $2 $3
