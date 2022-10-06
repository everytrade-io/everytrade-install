#!/usr/bin/env bash
set -exo pipefail

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --image)
            image="$2"
            shift # past argument
            shift # past value
        ;;
        --version)
            version="$2"
            shift # past argument
            shift # past value
        ;;
    esac
done

if [[ -z "$image" ]]; then
    image="everytrade-webapp"
fi

dockerComposeFile="docker-compose.yml"
dockerComposeFileCommit="master"
if [[ -f "$dockerComposeFile" ]]; then
    >&2 echo "$dockerComposeFile already exists."
    exit 2
fi

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/$dockerComposeFileCommit/docker-compose.yml" | \
  (
      if [[ -z "$version" ]]; then
          sed -e "s/^\(\s*image: registry\.everytrade\.io\/\)everytrade-webapp:\(.*\)$/\1$image:\2/"
      else
          sed -e "s/^\(\s*image: registry\.everytrade\.io\/\)everytrade-webapp:\(.*\)$/\1$image:$version/"
      fi
  ) > "$dockerComposeFile"
#sha256sum "$dockerComposeFile" | grep "$dockerComposeFileSha256"
if [[ -z "$DOCKER_HOST" ]]; then
    SUDO="sudo"
fi
$SUDO docker-compose -p everytrade pull
$SUDO docker-compose -p everytrade up -d
rm docker-compose.yml
