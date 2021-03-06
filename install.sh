#!/bin/bash

if [ "$(whoami)" != "root" ]
then
    echo -e "You must be root to run this script"
    exit 1
fi

set -e

MHN_HOME=`dirname "$(readlink -f "$0")"`
WWW_OWNER="www-data"
SCRIPTS="$MHN_HOME/scripts/"
cd $SCRIPTS

if [ -f /etc/redhat-release ]; then
    export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:$PATH
    #yum updates + health
    yum clean all -y
    yum update -y

    #Dump yum info for troubleshooting
    echo -e "Yum Repo List:\n"
    yum repolist
    echo -e "Yum Dev Group Packages:\n"
    yum grouplist | grep -i development
    echo -e "Attempting to install Dev Tools"
    yum groupinfo mark install "Development Tools"
    yum groupinfo mark convert "Development Tools"
    yum groupinstall "Development Tools" -y
    echo -e "Development Tools successfully installed\n"

    WWW_OWNER="nginx"
    ./install_sqlite.sh

    if [ ! -f /usr/local/bin/python2.7 ]; then
        echo "[`date`] Installing Python2.7 as a pre-req"
        ./install_python2.7.sh
    fi

    ./install_supervisord.sh
fi

echo "[`date`] Starting Installation of all MHN packages"

echo "[`date`] ========= Installing updates ========="
apt-get update -y && apt-get upgrade -y

echo "[`date`] ========= Installing hpfeeds ========="
./install_hpfeeds.sh

echo "[`date`] ========= Installing menmosyne ========="
./install_mnemosyne.sh

echo "[`date`] ========= Installing Honeymap ========="
./install_honeymap.sh

echo "[`date`] ========= Installing MHN Server ========="
./install_mhnserver.sh

echo "[`date`] ========= MHN Server Install Finished ========="
echo ""

while true;
do
    echo -n "Would you like to integrate with Splunk? (y/n) "
    read SPLUNK
    if [ "$SPLUNK" == "y" -o "$SPLUNK" == "Y" ]
    then
        echo -n "Splunk Forwarder Host: "
        read SPLUNK_HOST
        echo -n "Splunk Forwarder Port: "
        read SPLUNK_PORT
        echo "The Splunk Universal Forwarder will send all MHN logs to $SPLUNK_HOST:$SPLUNK_PORT"
        ./install_splunk_universalforwarder.sh "$SPLUNK_HOST" "$SPLUNK_PORT"
        ./install_hpfeeds-logger-splunk.sh
        break
    elif [ "$SPLUNK" == "n" -o "$SPLUNK" == "N" ]
    then
        echo "Skipping Splunk integration"
        echo "The splunk integration can be completed at a later time by running this:"
        echo "    cd /opt/mhn/scripts/"
        echo "    sudo ./install_splunk_universalforwarder.sh <SPLUNK_HOST> <SPLUNK_PORT>"
        echo "    sudo ./install_hpfeeds-logger-splunk.sh"
        break
    fi
done


while true;
do
    echo -n "Would you like to install ELK? (y/n) "
    read ELK
    if [ "$ELK" == "y" -o "$ELK" == "Y" ]
    then
        ./install_elk.sh
        break
    elif [ "$ELK" == "n" -o "$ELK" == "N" ]
    then
        echo "Skipping ELK installation"
        echo "The ELK installationg can be completed at a later time by running this:"
        echo "    cd /opt/mhn/scripts/"
        echo "    sudo ./install_elk.sh"
        break
    fi
done

chown $WWW_OWNER /var/log/mhn/mhn.log
supervisorctl restart mhn-celery-worker

echo "[`date`] ========= Setup HTTPS ========"
./setup_https.sh

echo "[`date`] ========= UFW Firewall Setup ========"
./install_ufw.sh

echo "[`date`] ========= Disable MHN Server Collector ========"
echo "The MHN server reports anonymized attack data back to Anomali, Inc. (formerly known as ThreatStream). If you are interested in this data please contact: modern-honey-network@googlegroups.com. This data reporting can be disabled by running the following command from the MHN server after completing the initial installation steps outlined above: /opt/mhn/scripts/disable_collector.sh"
echo -n "To disable enter 'y' and to leave collector enabled enter 'n' (y/n)"
read answer
if [ "$answer" == "y" -o "$answer" == "Y" ]
  /opt/mhn/scripts/disable_collector.sh
fi

echo "[`date`] Completed Installation of all MHN packages"
