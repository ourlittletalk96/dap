#!/bin/bash

#set -e
echo "[Reading environment settings]"
source ../env/settings.env
if [ -n ${LB_DNS} ]; then
    altnames="${LB_DNS},${STANDBY1_DNS},${STANDBY2_DNS}"
else
    altnames="${STANDBY1_DNS},${STANDBY2_DNS}"
fi

if [ -n ${SSL_LDAPS_PATH} ]; then
    ldap_port=636
else
    ldap_port=389
fi

read -sp 'Please enter SSH password for Node 1: ' _node1_pass
echo ''
read -sp 'Please enter SSH password for Node 2: ' _node2_pass
echo ''

### Check if containers are running ###

# Standby node 1 container
echo "[Checking if Conjur Standby containers are running]"
sshpass -p ${_node1_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} docker container ls -a | grep conjur-standby > /dev/null 2>&1
if [ ${?} -eq 0 ]; then
    echo "Standby container on node 1 is runnning."
    echo "Killing Standby container on node 1..."
    sshpass -p ${_node1_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} docker container rm -f conjur-standby > /dev/null 2>&1
else
    echo "Standby container on node 1 is not running."
fi

# Standby node 2 container
sshpass -p ${_node2_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} docker container ls -a | grep conjur-standby > /dev/null 2>&1
if [ ${?} -eq 0 ]; then
    echo "Standby container on node 2 is runnning."
    echo "Killing Standby container on node 1..."
    sshpass -p ${_node2_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} docker container rm -f conjur-standby > /dev/null 2>&1
else
    echo "Standby container on node 2 is not running."
fi


#### Run Standby Node 1 ####
echo "[Starting Conjur Standby Node 1 v${CONJUR_VERSION}]"
sshpass -p ${_node1_pass} ssh -i ${SSH_KEY}  -o PubkeyAuthentication=no root@${STANDBY1_DNS} docker run --name conjur-standby \
    -d \
    --mount type=bind,source=/tmp/master.key,target=/opt/conjur/keys/master.key \
    --restart=always \
    --security-opt seccomp:unconfined \
    --add-host=${LB_DNS}:${LB_IP} \
    --add-host=${STANDBY1_DNS}:${STANDBY1_IP} \
    --add-host=${STANDBY2_DNS}:${STANDBY2_IP} \
    --add-host=${MASTER_DNS}:${MASTER_IP} \
    -p "443:443" \
    -p "${ldap_port}:${ldap_port}" \
    -p "5432:5432" \
    -p "1999:1999" \
    ${IMAGE_NAME}:${CONJUR_VERSION}

#### Run Standby Node 2 ####
echo "[Starting Conjur Standby Node 2 v${CONJUR_VERSION}]"
sshpass -p ${_node2_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} docker run --name conjur-standby \
    -d \
    --mount type=bind,source=/tmp/master.key,target=/opt/conjur/keys/master.key \
    --restart=always \
    --security-opt seccomp:unconfined \
    --add-host=${LB_DNS}:${LB_IP} \
    --add-host=${STANDBY1_DNS}:${STANDBY1_IP} \
    --add-host=${STANDBY2_DNS}:${STANDBY2_IP} \
    --add-host=${MASTER_DNS}:${MASTER_IP} \
    -p "443:443" \
    -p "${ldap_port}:${ldap_port}" \
    -p "5432:5432" \
    -p "1999:1999" \
    ${IMAGE_NAME}:${CONJUR_VERSION}