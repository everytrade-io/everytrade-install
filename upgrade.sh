#!/usr/bin/env bash
set -exo pipefail

while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        --image)
            IMAGE="$2"
            shift # past argument
            shift # past value
        ;;
        --version)
            VERSION="$2"
            shift # past argument
            shift # past value
        ;;
        --install-commit)
            INSTALL_COMMIT="$2"
            shift # past argument
            shift # past value
        ;;
        --webapp-memory-limit)
            WEBAPP_MEMORY_LIMIT="$2"
            shift # past argument
            shift # past value
        ;;
    esac
done

PG_CONTAINER_NAME=everytrade_pgdb_1

if [[ -z "${INSTALL_COMMIT}" ]]; then
  INSTALL_COMMIT="master"
fi

if ! [ "$(docker ps -q -f name=${PG_CONTAINER_NAME})" ]; then
  curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/${INSTALL_COMMIT}/bin/migrate-to-postgresql.sh" > migrate-to-postgresql.sh
  chmod +x ./migrate-to-postgresql.sh
  ./migrate-to-postgresql.sh --install-commit ${INSTALL_COMMIT}
  rm ./migrate-to-postgresql.sh

  RESULT=$?
  if [ $RESULT -ne 0 ]; then
    echo "Migration failed. exiting."
    exit $RESULT
  fi
fi


if [[ -z "$IMAGE" ]]; then
    IMAGE="everytrade-webapp"
fi

DOCKER_COMPOSE_FILE="docker-compose.yml"
if [[ -f "${DOCKER_COMPOSE_FILE}" ]]; then
    >&2 echo "${DOCKER_COMPOSE_FILE} already exists."
    exit 2
fi

curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/${INSTALL_COMMIT}/docker-compose.yml" > "${DOCKER_COMPOSE_FILE}"

if [ "$(whoami)" == "ci" ]; then
    SUDO=""
elif [[ -z "$DOCKER_HOST" ]]; then
    SUDO="sudo"
fi

touch .env &&
echo "POSTGRES_PASSWORD=$(cat /run/secrets/pg)" >.env
echo "WHALEBOOKS_VERSION=${VERSION}" >> .env
echo "WHALEBOOKS_IMAGE=${IMAGE}" >> .env
if [[ -n "${WEBAPP_MEMORY_LIMIT}" ]]; then
  echo "WEBAPP_MEMORY_LIMIT=${WEBAPP_MEMORY_LIMIT}" >> .env
fi


$SUDO docker-compose -p everytrade pull
$SUDO docker-compose --compatibility -p everytrade up -d
rm .env docker-compose.yml
