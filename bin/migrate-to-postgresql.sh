#!/usr/bin/env bash
set -eo pipefail

while [[ $# -gt 0 ]]; do
  arg="$1"
  case $arg in
  --install-commit)
    INSTALL_COMMIT="$2"
    shift # past argument
    shift # past value
    ;;
  esac
done
if [[ -z "${INSTALL_COMMIT}" ]]; then
  INSTALL_COMMIT="master"
fi

NMIG_COMMIT=5fa0c9b8b5f0a8dfac2a888fc72ae317efdbf3a1
NMIG_DIR=nmig-${NMIG_COMMIT}

PG_CONTAINER_NAME=everytrade_pgdb_1
MYSQL_CONTAINER_NAME=everytrade_db_1

PG_PASSWORD_DIR=/run/secrets
PG_PASSWORD_FILE=${PG_PASSWORD_DIR}/pg

REQUIRED_DB_VERSION="2022.11.02.1"
REQUIRED_APP_VERSION="2022-11-02T1209"

if [[ -z "$DOCKER_HOST" ]]; then
  SUDO="sudo"
fi

function check_environment() {
  # check postgresql is not running
  if [ "$(docker ps -q -f name=${PG_CONTAINER_NAME})" ]; then
    echo >&2 "new db container ${PG_CONTAINER_NAME} is already running. This migration is for clean migration only. Exiting."
    exit 2
  fi

  # check old mysql DB is running
  if [ ! "$(docker ps -q -f name=${MYSQL_CONTAINER_NAME})" ]; then
    echo >&2 "Old mysql DB is not running. Please start it first."
    exit 2
  fi

  if ! command -v mysql &>/dev/null; then
    apt update && apt install -y mysql-client
  fi

  #check DB version
  SELECT_STMT="select max(version) from flyway_schema_history;"
  LAST_DB_VERSION=$(docker exec -i ${MYSQL_CONTAINER_NAME} mysql -ueverytrade -peverytrade everytrade <<<"${SELECT_STMT}" | tail -1)
  if [ "${LAST_DB_VERSION}" != "${REQUIRED_DB_VERSION}" ]; then
    echo
    echo "Your current DB version is ${LAST_DB_VERSION} but version ${REQUIRED_DB_VERSION} is required."
    echo "Please upgrade you app with following command and then run migration again: "
    echo "curl -s https://raw.githubusercontent.com/everytrade-io/everytrade-install/dac3f088c05368e311e86e724b6e8ba261c3d0f4/upgrade.sh | bash -s -- --version ${REQUIRED_APP_VERSION}"
    exit 1
  fi
}

function confirm_by_user() {
  echo
  echo "!!! This will migrate your whalebooks software to newer and faster database. !!!"
  echo "!!! Please be sure to make backup of your current database before proceeding !!!"
  echo "!!! Old database will be stopped but not deleted for possible problems and for need of migration revert. !!!"
  echo

  read -r -p "Please confirm you have backup of your database (y/n)?" REPLY </dev/tty
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi

  echo
  read -r -p "Are you sure you want to continue with upgrade (y/n)?" REPLY </dev/tty
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    [[ "$0" == "$BASH_SOURCE" ]] && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
  fi
  echo
}

function prepare_environment() {
  # install prerequisites
  apt update && apt install -y jq npm unzip mysql-client

  mkdir -p migration-workdir && cd ./migration-workdir

  #download compose file
  DOCKER_COMPOSE_FILE="docker-compose.yml"
  if [[ -f "${DOCKER_COMPOSE_FILE}" ]]; then
    >&2 echo "${DOCKER_COMPOSE_FILE} already exists."
    exit 2
  fi
  curl "https://raw.githubusercontent.com/everytrade-io/everytrade-install/${INSTALL_COMMIT}/docker-compose.yml" > "${DOCKER_COMPOSE_FILE}"

  echo "stopping webapp"
  $SUDO docker-compose -p everytrade stop webapp
}

function check_password() {
  if [ ! -f "${PG_PASSWORD_FILE}" ]; then
    echo "!!! Be sure to make backup of your database password. We have no way how to get to your data without your password !!!"
    echo "Please enter your new database password:"
    read -s -r PASSWORD </dev/tty
    mkdir -p ${PG_PASSWORD_DIR}
    touch ${PG_PASSWORD_FILE}
    echo "${PASSWORD}" >${PG_PASSWORD_FILE}
  else
    echo "Using existing password from ${PG_PASSWORD_FILE}"
  fi

  touch .env
  echo "POSTGRES_PASSWORD=$(cat $PG_PASSWORD_FILE)" >.env
}

function start_new_pgdb() {
  echo "starting container with new database"
  $SUDO docker-compose -p everytrade pull
  $SUDO docker-compose -p everytrade up -d pgdb

  # check postgresql is running successfully
  if [ ! "$(docker ps -q -f name=${PG_CONTAINER_NAME})" ]; then
    echo >&2 "New postgresql DB is not running! Please check postgresql container logs"
    exit 2
  fi
}

function migrate_with_nmig() {
  # download and unzip nmig
  echo "Downloading migration tool"
  curl -L --output nmig.zip https://github.com/AnatolyUss/nmig/archive/${NMIG_COMMIT}.zip
  unzip nmig.zip

  # build nmig
  echo "Configuring migration tool"
  cd ./${NMIG_DIR}
  npm install
  npm run build

  #configure nmig config.json file
  MYSQL_HOST=$(docker container inspect ${MYSQL_CONTAINER_NAME} | jq '.[].NetworkSettings.Networks.everytrade_default.IPAddress' | tr -d \")
  POSTGRES_HOST=$(docker container inspect ${PG_CONTAINER_NAME} | jq '.[].NetworkSettings.Networks.everytrade_default.IPAddress' | tr -d \")
  TMP_FILE=$(mktemp)
  JQ_CONF='.source.host="'"${MYSQL_HOST}"'"'
  JQ_CONF+=' | .source.database="everytrade"'
  JQ_CONF+=' | .source.user="everytrade"'
  JQ_CONF+=' | .source.password="everytrade"'
  JQ_CONF+=' | .target.host="'"${POSTGRES_HOST}"'"'
  JQ_CONF+=' | .target.database="whalebooks"'
  JQ_CONF+=' | .target.user="whalebooks"'
  JQ_CONF+=' | .target.password=$pgpass'
  JQ_CONF+=' | .exclude_tables=["flyway_schema_history"]'
  jq --arg pgpass "$(cat ${PG_PASSWORD_FILE})" "${JQ_CONF}" ./config/config.json >"${TMP_FILE}" && mv "${TMP_FILE}" ./config/config.json

  # start migration
  echo "Starting migrating data to postgresql"
  npm start

  echo "Migration complete. Please check above logs to ensure everything was smooth."
  echo "Old database container ${MYSQL_CONTAINER_NAME} is stopped but not deleted. Consider backup and removal of container."
}

function clean_up() {
  cd ../
  docker stop ${MYSQL_CONTAINER_NAME}
  rm docker-compose.yml
  rm .env
}

check_environment
confirm_by_user
prepare_environment
check_password
start_new_pgdb
migrate_with_nmig
clean_up
exit 0
