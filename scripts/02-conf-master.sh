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

#docker exec conjur-master evoke keys encrypt /opt/conjur/keys/master.key
#docker exec conjur-master evoke keys unlock /opt/conjur/keys/master.key
#docker exec conjur-master sv start conjur