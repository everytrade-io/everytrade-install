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

# Refuse to upgrade if the pgdb volume still holds a PG15 cluster — the new
# pgdb image is PG17 and would fail to start on PG15 data files. The operator
# must run bin/upgrade-pgdb-15-to-17.sh first.
PG_VOLUME_NAME="everytrade_db-data"
if docker volume inspect "${PG_VOLUME_NAME}" >/dev/null 2>&1; then
  CLUSTER_VERSION="$(docker run --rm -v "${PG_VOLUME_NAME}:/v" alpine \
    sh -c "cat /v/data/PG_VERSION 2>/dev/null || true")"
  if [ "${CLUSTER_VERSION}" = "15" ]; then
    cat >&2 <<EOF
Detected PostgreSQL 15 data in volume ${PG_VOLUME_NAME}, but the new pgdb image
ships PostgreSQL 17 and cannot read PG15 data files directly.

Run the one-shot migration first, then re-run this upgrade:

  curl -s https://raw.githubusercontent.com/everytrade-io/everytrade-install/${INSTALL_COMMIT}/bin/upgrade-pgdb-15-to-17.sh \\
    | sudo bash -s -- --install-commit ${INSTALL_COMMIT}

EOF
    exit 3
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
echo "POSTGRES_PASSWORD=$(cat /etc/secrets/pg)" >.env
echo "WHALEBOOKS_VERSION=${VERSION}" >> .env
echo "WHALEBOOKS_IMAGE=${IMAGE}" >> .env
if [[ -n "${WEBAPP_MEMORY_LIMIT}" ]]; then
  echo "WEBAPP_MEMORY_LIMIT=${WEBAPP_MEMORY_LIMIT}" >> .env
fi


$SUDO docker stop everytrade_webapp_1
$SUDO docker compose -p everytrade pull
$SUDO docker compose --compatibility -p everytrade up -d
rm .env docker-compose.yml
