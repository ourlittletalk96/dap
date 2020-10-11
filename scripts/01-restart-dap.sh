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

### Check if containers are running ###
# Master Container
echo "[Checking if Conjur Master container is running]"
docker container ls -a | grep conjur-master > /dev/null 2>&1
if [ ${?} -eq 0 ]; then
    echo "Master container is runnning."
    echo "Killing Master container..."
    docker container rm -f conjur-master > /dev/null 2>&1
else
    echo "Master container is not running."
fi

# Standby node 1 container
echo "[Checking if Conjur Standby containers are running]"
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} docker container ls -a | grep conjur-standby > /dev/null 2>&1
if [ ${?} -eq 0 ]; then
    echo "Standby container on node 1 is runnning."
    echo "Killing Standby container on node 1..."
    ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} docker container rm -f conjur-standby > /dev/null 2>&1
else
    echo "Standby container on node 1 is not running."
fi

# Standby node 2 container
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} docker container ls -a | grep conjur-standby > /dev/null 2>&1
if [ ${?} -eq 0 ]; then
    echo "Standby container on node 2 is runnning."
    echo "Killing Standby container on node 1..."
    ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} docker container rm -f conjur-standby > /dev/null 2>&1
else
    echo "Standby container on node 2 is not running."
fi

#### Run Master Node ####
echo "[Starting Conjur Master Node v${CONJUR_VERSION}]"
docker run --name conjur-master \
    -d \
    --mount type=volume,dst=/opt/conjur/policy,volume-driver=local,volume-opt=type=none,volume-opt=o=bind,volume-opt=device=${CONJUR_CONF_PATH}/policy \
    --mount type=volume,dst=/opt/conjur/keys,volume-driver=local,volume-opt=type=none,volume-opt=o=bind,volume-opt=device=${CONJUR_CONF_PATH}/secrets \
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

docker exec conjur-master evoke configure master \
    -h ${MASTER_DNS} \
    --master-altnames "${altnames}" \
    -p ${ADMIN_PASSPHRASE} \
    ${ORG_ACCOUNT_NAME}

docker exec conjur-master evoke keys encrypt /opt/conjur/keys/master.key
docker exec conjur-master evoke keys unlock /opt/conjur/keys/master.key
docker exec conjur-master sv start conjur

#### Run Standby Node 1 ####
echo "[Starting Conjur Standby Node 1 v${CONJUR_VERSION}]"
ssh -i ${SSH_KEY}  -o PubkeyAuthentication=no root@${STANDBY1_DNS} docker run --name conjur-standby \
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
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} docker run --name conjur-standby \
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

echo "[Seeding to Standby node 1]"
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${MASTER_DNS} "docker exec conjur-master evoke seed standby ${STANDBY1_DNS}" | ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} "docker exec -i conjur-standby evoke unpack seed -"
echo "[Seeding to Standby node 2]"
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${MASTER_DNS} "docker exec conjur-master evoke seed standby ${STANDBY2_DNS}" | ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} "docker exec -i conjur-standby evoke unpack seed -"

echo "[Configuring Standby node 1]"
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} "docker exec conjur-standby evoke keys exec -m /opt/conjur/keys/master.key -- evoke configure standby"

echo "[Configuring Standby node 2]"
ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} "docker exec conjur-standby evoke keys exec -m /opt/conjur/keys/master.key -- evoke configure standby"

echo "[Commencing replication]"
docker exec conjur-master evoke replication sync
### Healthcheck on Master Node ###
echo "[Checking Master node health]"
curl https://${MASTER_DNS}/health -k
echo "[Conjur Cluster is running successfully.]"