#!/usr/bin/env bash
set -exo pipefail

dockerComposeFile="docker-compose.yml"
dockerComposeFileCommit="master"
dockerComposeFileSha256="f789db6d327d0664e452cca266fb197d3d6baa3d4c5899ef5b2d78af2b052052"
if [[ -f "$dockerComposeFile" ]]; then
    >&2 echo "$dockerComposeFile already exists."
    exit 2
fi

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/$dockerComposeFileCommit/docker-compose.yml" -o "$dockerComposeFile"
sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
sudo docker-compose pull
sudo docker-compose up -d
