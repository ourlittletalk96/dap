#!/bin/bash

#set -e
source ../env/settings.env
echo "[Checking Conjur Appliance Image"]

#### Master ####
docker images | egrep "${IMAGE_NAME}.*?${CONJUR_VERSION}" > /dev/null 2>&1
if [ ${?} -eq 0 ] ; then
    echo "Existing image found on master node. Skipping..."
    #docker image rm -f ${IMAGE_NAME}:${CONJUR_VERSION}
else
    echo "Image is not found on master node. Loading image ${CONJUR_VERSION}"
    docker load -i ../media/conjur-appliance-${CONJUR_VERSION}.tar.gz
fi

#### Standby Node 1 ####
ssh -i ${SSH_KEY} root@${STANDBY1_DNS} docker images | egrep "${IMAGE_NAME}.*?${CONJUR_VERSION}" > /dev/null 2>&1
if [ ${?} -eq 0 ] ; then
    echo "Existing image found on standby node 1. Skipping..."
    #docker image rm -f ${IMAGE_NAME}:${CONJUR_VERSION}
    
else
    echo "Image is not found on standby node 1. Loading image ${CONJUR_VERSION}"
    # Check if file exists
    ssh -i ${SSH_KEY} root@${STANDBY1_DNS} stat /tmp/conjur-appliance-${CONJUR_VERSION}.tar.gz > /dev/null 2>&1
    if [ ${?} -eq 1 ]; then
        scp -i ${SSH_KEY} ../media/conjur-appliance-${CONJUR_VERSION}.tar.gz root@${STANDBY1_DNS}:/tmp/
    fi
    ssh -i ${SSH_KEY} root@${STANDBY1_DNS} docker load -i /tmp/conjur-appliance-${CONJUR_VERSION}.tar.gz
fi

#### Standby Node 2 ####
ssh -i ${SSH_KEY} root@${STANDBY2_DNS} docker images | egrep "${IMAGE_NAME}.*?${CONJUR_VERSION}" > /dev/null 2>&1
if [ ${?} -eq 0 ] ; then
    echo "Existing image found on standby node 2. Skipping..."
    #docker image rm -f ${IMAGE_NAME}:${CONJUR_VERSION}
    
else
    echo "Image is not found on standby node 2. Loading image ${CONJUR_VERSION}"
    # Check if file exists
    ssh -i ${SSH_KEY} root@${STANDBY2_DNS} stat /tmp/conjur-appliance-${CONJUR_VERSION}.tar.gz > /dev/null 2>&1
    if [ ${?} -eq 1 ]; then
        scp -i ${SSH_KEY} ../media/conjur-appliance-${CONJUR_VERSION}.tar.gz root@${STANDBY2_DNS}:/tmp/
    fi
    ssh -i ${SSH_KEY} root@${STANDBY2_DNS} docker load -i /tmp/conjur-appliance-${CONJUR_VERSION}.tar.gz
fi

#### Post installation tasks ####
## Generate 32-bit master key on Master node
openssl rand 32 > ../secrets/master.key
scp -i ${SSH_KEY} ../secrets/master.key root@${STANDBY1_DNS}:/tmp/
scp -i ${SSH_KEY} ../secrets/master.key root@${STANDBY2_DNS}:/tmp/

