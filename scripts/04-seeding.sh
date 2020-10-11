#!/bin/bash

#set -e
echo "[Reading environment settings]"
source ../env/settings.env
if [ -z "${_node1_pass}" ] || [ -z "${_node2_pass}"]; then 
    read -sp 'Please enter SSH password for Node 1: ' _node1_pass
    echo ''
    read -sp 'Please enter SSH password for Node 2: ' _node2_pass
    echo ''
fi

echo "[Seeding to Standby node 1]"
sshpass -p ${_node1_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${MASTER_DNS} "docker exec conjur-master evoke seed standby ${STANDBY1_DNS}" | sshpass -p ${_node1_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} "docker exec -i conjur-standby evoke unpack seed -"
echo "[Seeding to Standby node 2]"
sshpass -p ${_node2_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${MASTER_DNS} "docker exec conjur-master evoke seed standby ${STANDBY2_DNS}" | sshpass -p ${_node2_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} "docker exec -i conjur-standby evoke unpack seed -"

echo "[Configuring Standby node 1]"
sshpass -p ${_node1_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY1_DNS} "docker exec conjur-standby evoke keys exec -m /opt/conjur/keys/master.key -- evoke configure standby"

echo "[Configuring Standby node 2]"
sshpass -p ${_node2_pass} ssh -i ${SSH_KEY} -o PubkeyAuthentication=no root@${STANDBY2_DNS} "docker exec conjur-standby evoke keys exec -m /opt/conjur/keys/master.key -- evoke configure standby"

echo "[Commencing replication]"
docker exec conjur-master evoke replication sync
### Healthcheck on Master Node ###
echo "[Checking Master node health]"
curl https://${MASTER_DNS}/health -k
echo "[Conjur Cluster is running successfully.]"