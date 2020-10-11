#!/bin/bash

source ../env/settings.env
docker images | egrep "cyberark/conjur-cli" > /dev/null 2>&1
if [ ${?} -eq 1 ]; then
    echo "Conjur-CLI image not found."
    echo "Loading Conjur-CLI image..."
    docker load -i ../media/conjur-cli.tar > /dev/null 2>&1
    if [ ${?} -eq 1 ]; then
        echo "Conjur-CLI image is loaded."
    fi
else
    echo "Conjur-CLI image is loaded."
fi
docker run --rm -it --name conjur-client -v /opt/docker-conjur/policy:/opt/conjur/policy --link conjur-master cyberark/conjur-cli:5