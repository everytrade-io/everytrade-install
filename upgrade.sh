#!/usr/bin/env bash
set -exo pipefail

dockerComposeFile="docker-compose.yml"
dockerComposeFileCommit="3a4899b6f6d2cd487469f3c6b8dc10d84e664b22"
dockerComposeFileSha256="175bcfd2bfc651563781451140946b81bbb5dc1f8f71ba992b1a259e72b4bebf"
if [[ -f "$dockerComposeFile" ]]; then
    >&2 echo "$dockerComposeFile already exists."
    exit 2
fi

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/$dockerComposeFileCommit/docker-compose.yml" -o "$dockerComposeFile"
sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
sudo docker-compose pull
sudo docker-compose up -d
