#!/usr/bin/env bash
# Major Postgres upgrade 15 -> 17 for Whalebooks (everytrade) production / stage.
#
# Performs a dump/restore migration because PG17 cannot read PG15 data files
# directly. Steps:
#   1) start the OLD pgdb container (PG15) if not running
#   2) pg_dumpall to a gzipped file under ${BACKUP_DIR}
#   3) snapshot the entire PG15 data volume into a backup volume (for rollback)
#   4) wipe the existing data volume
#   5) pull + start the NEW pgdb container (PG17) via docker compose
#   6) psql-restore the dump
#
# The caller is expected to invoke this BEFORE everytrade-install/upgrade.sh.
# After this script succeeds, the normal upgrade.sh will recreate the webapp.
#
# Run as root on the production / stage host. Idempotent: re-running on an
# already-migrated volume (PG_VERSION=17) is a no-op.

set -eo pipefail

# -----------------------------------------------------------------------------
# CLI args
# -----------------------------------------------------------------------------
ASSUME_YES=false
INSTALL_COMMIT=""
DOCKER_COMPOSE_URL=""
BACKUP_DIR_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            ASSUME_YES=true; shift ;;
        --install-commit)
            INSTALL_COMMIT="$2"; shift 2 ;;
        --compose-url)
            DOCKER_COMPOSE_URL="$2"; shift 2 ;;
        --backup-dir)
            BACKUP_DIR_OVERRIDE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,30p' "$0"; exit 0 ;;
        *)
            echo >&2 "Unknown argument: $1"
            exit 64 ;;
    esac
done

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
PROJECT_NAME="everytrade"
PG_SERVICE="pgdb"
PG_CONTAINER_NAME="${PROJECT_NAME}_${PG_SERVICE}_1"
WEBAPP_CONTAINER_NAME="${PROJECT_NAME}_webapp_1"
VOLUME_NAME="${PROJECT_NAME}_db-data"

PG_USER="whalebooks"
PG_DB="whalebooks"
PG_PASSWORD_FILE="/etc/secrets/pg"

BACKUP_DIR="${BACKUP_DIR_OVERRIDE:-/var/backups/everytrade-pgdb}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DUMP_FILE="${BACKUP_DIR}/pre-pg17-${TIMESTAMP}.sql.gz"
BACKUP_VOLUME="${VOLUME_NAME}-pg15-backup-${TIMESTAMP}"

[[ -z "${INSTALL_COMMIT}" ]] && INSTALL_COMMIT="master"
[[ -z "${DOCKER_COMPOSE_URL}" ]] && \
    DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/everytrade-io/everytrade-install/${INSTALL_COMMIT}/docker-compose.yml"

if [[ -z "${DOCKER_HOST}" && "$(id -u)" != "0" ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log() { printf '\033[1;34m[migrate-pg17]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[migrate-pg17]\033[0m %s\n' "$*" >&2; exit 1; }

require_cmd() {
    command -v "$1" >/dev/null || die "Required command not found: $1"
}

confirm() {
    if [[ "${ASSUME_YES}" == "true" ]]; then return 0; fi
    read -r -p "$1 [y/N] " REPLY </dev/tty
    [[ "${REPLY}" =~ ^[Yy]$ ]] || die "Aborted by user."
}

read_pg_version() {
    # Returns content of PG_VERSION inside the data volume, empty string if absent.
    $SUDO docker run --rm -v "${VOLUME_NAME}:/v" alpine \
        sh -c "cat /v/data/PG_VERSION 2>/dev/null || true"
}

wait_for_pg_ready() {
    local container="$1" attempts=60
    log "Waiting for ${container} to accept connections..."
    for _ in $(seq 1 ${attempts}); do
        if $SUDO docker exec "${container}" pg_isready -U "${PG_USER}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    die "${container} did not become ready in $((attempts * 2))s"
}

# -----------------------------------------------------------------------------
# Pre-flight
# -----------------------------------------------------------------------------
require_cmd docker
require_cmd curl
require_cmd gzip

[[ -f "${PG_PASSWORD_FILE}" ]] || die "Missing ${PG_PASSWORD_FILE} — cannot connect to DB."

if ! $SUDO docker volume inspect "${VOLUME_NAME}" >/dev/null 2>&1; then
    die "Volume ${VOLUME_NAME} not found. Run install.sh first; nothing to migrate."
fi

CLUSTER_VERSION="$(read_pg_version)"
case "${CLUSTER_VERSION}" in
    17)
        log "Volume already at PG17. Nothing to do."
        exit 0
        ;;
    15) ;;  # the expected migration source
    "")
        die "Could not detect PG cluster version in ${VOLUME_NAME} (no PG_VERSION file)."
        ;;
    *)
        die "Unexpected PG cluster version '${CLUSTER_VERSION}' in ${VOLUME_NAME}. Expected 15."
        ;;
esac

log "Detected PG15 cluster in ${VOLUME_NAME}. Will migrate to PG17."
log ""
log "  Dump file:     ${DUMP_FILE}"
log "  Backup volume: ${BACKUP_VOLUME}"
log ""
confirm "This will stop the webapp, dump the database, recreate the pgdb volume, and restore. Continue?"

$SUDO mkdir -p "${BACKUP_DIR}"

# -----------------------------------------------------------------------------
# Workdir + compose file (needed for `docker compose up -d pgdb` after wipe)
# -----------------------------------------------------------------------------
WORKDIR="$(mktemp -d)"
trap '$SUDO rm -rf "${WORKDIR}"' EXIT
cd "${WORKDIR}"

curl -fsSL "${DOCKER_COMPOSE_URL}" -o docker-compose.yml
echo "POSTGRES_PASSWORD=$($SUDO cat "${PG_PASSWORD_FILE}")" > .env
# WHALEBOOKS_VERSION/IMAGE not strictly needed for pgdb-only `up`, but compose
# substitutes defaults so this is fine.

# -----------------------------------------------------------------------------
# 1. Stop webapp
# -----------------------------------------------------------------------------
if $SUDO docker ps -q -f "name=^${WEBAPP_CONTAINER_NAME}$" | grep -q .; then
    log "Stopping ${WEBAPP_CONTAINER_NAME}..."
    $SUDO docker stop "${WEBAPP_CONTAINER_NAME}" >/dev/null
fi

# -----------------------------------------------------------------------------
# 2. Make sure the OLD pgdb container is running (we need it for pg_dumpall)
# -----------------------------------------------------------------------------
if ! $SUDO docker ps -q -f "name=^${PG_CONTAINER_NAME}$" | grep -q .; then
    if $SUDO docker ps -a -q -f "name=^${PG_CONTAINER_NAME}$" | grep -q .; then
        log "Starting existing ${PG_CONTAINER_NAME} (still on PG15 image)..."
        $SUDO docker start "${PG_CONTAINER_NAME}" >/dev/null
    else
        die "No ${PG_CONTAINER_NAME} container exists. Cannot dump without an old PG15 container.
Start it manually with the previous docker-compose.yml first, or restore from backup."
    fi
fi
wait_for_pg_ready "${PG_CONTAINER_NAME}"

# -----------------------------------------------------------------------------
# 3. pg_dumpall (roles + databases) → gzip
# -----------------------------------------------------------------------------
log "Dumping cluster via pg_dumpall to ${DUMP_FILE}..."
# --clean / --if-exists makes the restore script idempotent if re-run.
$SUDO docker exec "${PG_CONTAINER_NAME}" \
    pg_dumpall -U "${PG_USER}" --clean --if-exists \
    | gzip -9 > "${DUMP_FILE}"
DUMP_SIZE="$(du -h "${DUMP_FILE}" | cut -f1)"
log "Dump complete (${DUMP_SIZE})."

# -----------------------------------------------------------------------------
# 4. Stop old PG15 container, snapshot volume, then wipe data
# -----------------------------------------------------------------------------
log "Stopping ${PG_CONTAINER_NAME}..."
$SUDO docker stop "${PG_CONTAINER_NAME}" >/dev/null
$SUDO docker rm "${PG_CONTAINER_NAME}" >/dev/null

log "Snapshotting PG15 volume to ${BACKUP_VOLUME} (rollback safety net)..."
$SUDO docker volume create "${BACKUP_VOLUME}" >/dev/null
$SUDO docker run --rm \
    -v "${VOLUME_NAME}:/from:ro" \
    -v "${BACKUP_VOLUME}:/to" \
    alpine sh -c "cp -a /from/. /to/"

log "Wiping ${VOLUME_NAME} so PG17 can initialise a fresh cluster..."
$SUDO docker run --rm -v "${VOLUME_NAME}:/v" alpine \
    sh -c "rm -rf /v/data /v/lost+found 2>/dev/null; find /v -mindepth 1 -delete"

# -----------------------------------------------------------------------------
# 5. Pull new image + start fresh PG17 pgdb
# -----------------------------------------------------------------------------
log "Pulling new pgdb image..."
$SUDO docker compose -p "${PROJECT_NAME}" -f docker-compose.yml pull "${PG_SERVICE}"

log "Starting fresh PG17 ${PG_CONTAINER_NAME}..."
$SUDO docker compose -p "${PROJECT_NAME}" -f docker-compose.yml --compatibility up -d "${PG_SERVICE}"
wait_for_pg_ready "${PG_CONTAINER_NAME}"

# Sanity: confirm we're really on PG17 now.
SERVER_VERSION="$($SUDO docker exec "${PG_CONTAINER_NAME}" \
    psql -U "${PG_USER}" -d postgres -tAc "SHOW server_version_num;" | tr -d '[:space:]')"
if [[ -z "${SERVER_VERSION}" || "${SERVER_VERSION}" -lt 170000 ]]; then
    die "New container reports server_version_num=${SERVER_VERSION:-unknown}; expected >= 170000.
The old data is preserved in volume ${BACKUP_VOLUME} — see rollback notes below."
fi
log "New cluster reports server_version_num=${SERVER_VERSION}. OK."

# -----------------------------------------------------------------------------
# 6. Restore dump
# -----------------------------------------------------------------------------
log "Restoring dump into PG17..."
# psql exits non-zero on the first error; --set ON_ERROR_STOP=on makes that strict.
zcat "${DUMP_FILE}" \
    | $SUDO docker exec -i "${PG_CONTAINER_NAME}" \
        psql -U "${PG_USER}" -d postgres \
             --set ON_ERROR_STOP=on \
             --quiet

log "Restore complete."

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
TABLE_COUNT="$($SUDO docker exec "${PG_CONTAINER_NAME}" \
    psql -U "${PG_USER}" -d "${PG_DB}" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" \
    | tr -d '[:space:]')"
EXT_COUNT="$($SUDO docker exec "${PG_CONTAINER_NAME}" \
    psql -U "${PG_USER}" -d "${PG_DB}" -tAc \
    "SELECT count(*) FROM pg_extension WHERE extname='moddatetime';" \
    | tr -d '[:space:]')"

log "Tables in public schema: ${TABLE_COUNT}"
log "moddatetime extension installed: ${EXT_COUNT}"
[[ "${TABLE_COUNT}" -gt 0 ]] || die "Restored DB has no tables — investigate before bringing webapp up."
[[ "${EXT_COUNT}" == "1" ]]   || die "moddatetime extension missing — triggers on updated_at will fail."

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
cat <<EOF

==============================================================================
PostgreSQL 15 -> 17 migration completed.

Artifacts kept for rollback (delete manually after a few days of stable run):
  - SQL dump:        ${DUMP_FILE}
  - Volume snapshot: ${BACKUP_VOLUME}  (full PG15 datadir)

Next steps:
  1) Run the normal upgrade to bring the webapp back up:
       curl -s https://raw.githubusercontent.com/everytrade-io/everytrade-install/${INSTALL_COMMIT}/upgrade.sh \\
         | sudo bash -s -- --version <WHALEBOOKS_VERSION>
  2) Verify the app, then clean up rollback artifacts:
       sudo rm ${DUMP_FILE}
       sudo docker volume rm ${BACKUP_VOLUME}

Rollback (if something is wrong, BEFORE running upgrade.sh again):
  1) sudo docker stop ${PG_CONTAINER_NAME} && sudo docker rm ${PG_CONTAINER_NAME}
  2) sudo docker run --rm -v ${VOLUME_NAME}:/to -v ${BACKUP_VOLUME}:/from:ro alpine sh -c "find /to -mindepth 1 -delete && cp -a /from/. /to/"
  3) Revert docker-compose.yml to the previous pgdb image tag, run docker compose up -d pgdb webapp.
==============================================================================
EOF
