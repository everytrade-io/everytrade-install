#!/usr/bin/env bash
set -exo pipefail

dockerComposeFile="docker-compose.yml"
dockerComposeFileSha256="0e59080b852118c3392da0ed9eb7f67abdb5885172c4060e9eedc1de9c68957e"
if [[ -f "$dockerComposeFile" ]]; then
    >&2 echo "$dockerComposeFile already exists."
    exit 2
fi

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/01373871596d0e46d724b960fbadde73a0a79130/docker-compose.yml" -o "$dockerComposeFile"
sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
sudo docker-compose pull
sudo docker-compose up -d