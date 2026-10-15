#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-root@178.173.250.250}"
CONTAINER_NAME="${CONTAINER_NAME:-trainbot-crm}"
IDENTITY_FILE="${IDENTITY_FILE:-$HOME/.ssh/id_rsa}"
LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
STAGING="/tmp/trainbot-release-${STAMP}"
EXPECTED_VERSION="${APP_VERSION:-7.5.0}"

SSH_ARGS=(-o StrictHostKeyChecking=yes -o IdentitiesOnly=yes)
if [[ -f "$IDENTITY_FILE" ]]; then
    SSH_ARGS+=(-i "$IDENTITY_FILE")
fi
SSH=(ssh "${SSH_ARGS[@]}" "$TARGET")
RSYNC_SSH="ssh -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes"
if [[ -f "$IDENTITY_FILE" ]]; then
    RSYNC_SSH+=" -i $IDENTITY_FILE"
fi

echo "[1/5] Checking remote Docker and locating the current Compose project"
REMOTE_DIR="$(${SSH[@]} "
    set -e
    command -v docker >/dev/null
    docker compose version >/dev/null
    dir=\$(docker inspect '$CONTAINER_NAME' --format '{{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}' 2>/dev/null || true)
    if [ -z \"\$dir\" ]; then dir=/opt/trainbot; fi
    printf '%s' \"\$dir\"
")"

if [[ -z "$REMOTE_DIR" || "$REMOTE_DIR" != /* ]]; then
    echo "Unable to determine a safe remote project directory" >&2
    exit 1
fi

echo "Remote project: $REMOTE_DIR"
echo "[2/5] Uploading release to staging"
${SSH[@]} "rm -rf '$STAGING' && mkdir -p '$STAGING/outputs'"
rsync -az --delete -e "$RSYNC_SSH" \
    --exclude '__pycache__/' --exclude '*.pyc' \
    "$LOCAL_ROOT/backend/" "$TARGET:$STAGING/backend/"
rsync -az --delete -e "$RSYNC_SSH" \
    "$LOCAL_ROOT/frontend/" "$TARGET:$STAGING/frontend/"
rsync -az --delete -e "$RSYNC_SSH" \
    "$LOCAL_ROOT/outputs/trainbot-equipment-library/" \
    "$TARGET:$STAGING/outputs/trainbot-equipment-library/"
rsync -az -e "$RSYNC_SSH" \
    "$LOCAL_ROOT/Dockerfile" "$LOCAL_ROOT/docker-compose.yml" "$LOCAL_ROOT/Caddyfile" "$LOCAL_ROOT/.dockerignore" "$LOCAL_ROOT/README.md" \
    "$TARGET:$STAGING/"
rsync -az --delete -e "$RSYNC_SSH" \
    "$LOCAL_ROOT/scripts/" "$TARGET:$STAGING/scripts/"

echo "[3/5] Backing up the running release and persistent data"
${SSH[@]} "
    set -Eeuo pipefail
    mkdir -p /root/trainbot-deploy-backups '$REMOTE_DIR'
    previous=\$(docker inspect '$CONTAINER_NAME' --format '{{.Image}}' 2>/dev/null || true)
    if [ -n \"\$previous\" ] && docker image inspect \"\$previous\" >/dev/null 2>&1; then
        rollback_tag='trainbot-crm:rollback-${STAMP}'
        docker tag \"\$previous\" \"\$rollback_tag\"
        printf '%s' \"\$rollback_tag\" > '$REMOTE_DIR/.previous-image'
    else
        : > '$REMOTE_DIR/.previous-image'
    fi
    backup=/root/trainbot-deploy-backups/trainbot_${STAMP}.tar.gz
    if [ -d '$REMOTE_DIR' ]; then
        tar -C '$REMOTE_DIR' \
            --exclude='./data/backups' \
            -czf \"\$backup\" \
            Dockerfile docker-compose.yml Caddyfile .env backend frontend outputs data files 2>/dev/null || true
    fi
    test -s \"\$backup\" || echo 'Existing release was empty; no archive created'
    printf 'Backup: %s\n' \"\$backup\"
"

echo "[4/5] Installing release and rebuilding container"
${SSH[@]} "
    set -Eeuo pipefail
    mkdir -p '$REMOTE_DIR/backend' '$REMOTE_DIR/frontend' '$REMOTE_DIR/outputs' '$REMOTE_DIR/data' '$REMOTE_DIR/files'
    rm -rf '$REMOTE_DIR/backend' '$REMOTE_DIR/frontend' '$REMOTE_DIR/outputs/trainbot-equipment-library'
    mv '$STAGING/backend' '$REMOTE_DIR/backend'
    mv '$STAGING/frontend' '$REMOTE_DIR/frontend'
    mv '$STAGING/outputs/trainbot-equipment-library' '$REMOTE_DIR/outputs/trainbot-equipment-library'
    cp '$STAGING/Dockerfile' '$REMOTE_DIR/Dockerfile'
    cp '$STAGING/docker-compose.yml' '$REMOTE_DIR/docker-compose.yml'
    rm -rf '$REMOTE_DIR/Caddyfile'
    cp '$STAGING/Caddyfile' '$REMOTE_DIR/Caddyfile'
    cp '$STAGING/.dockerignore' '$REMOTE_DIR/.dockerignore'
    cp '$STAGING/README.md' '$REMOTE_DIR/README.md'
    rm -rf '$REMOTE_DIR/scripts'
    mv '$STAGING/scripts' '$REMOTE_DIR/scripts'
    rm -rf '$STAGING'
    cd '$REMOTE_DIR'
    test -s .env
    docker compose config >/dev/null
    docker compose up -d --build --remove-orphans
"

echo "[5/5] Waiting for health check"
${SSH[@]} "
    set -e
    for attempt in \$(seq 1 30); do
        status=\$(docker inspect '$CONTAINER_NAME' --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' 2>/dev/null || true)
        version=\$(curl -fsS --max-time 4 http://127.0.0.1:8080/api/health 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get(\"version\", \"\"))' 2>/dev/null || true)
        if [ \"\$status\" = healthy ] && [ \"\$version\" = '$EXPECTED_VERSION' ]; then
            docker ps --filter name='$CONTAINER_NAME' --format 'Container: {{.Names}} | {{.Status}} | {{.Ports}}'
            curl -fsS http://127.0.0.1:8080/api/health
            exit 0
        fi
        sleep 3
    done
    docker logs --tail 120 '$CONTAINER_NAME' >&2 || true
    previous=\$(cat '$REMOTE_DIR/.previous-image' 2>/dev/null || true)
    if [ -n \"\$previous\" ] && docker image inspect \"\$previous\" >/dev/null 2>&1; then
        echo 'Health check failed, restoring previous image' >&2
        docker tag \"\$previous\" trainbot-crm:latest
        cd '$REMOTE_DIR'
        docker compose up -d --no-build --force-recreate
    fi
    exit 1
"

echo
echo "Deployment completed: https://train.178-173-250-250.sslip.io/"
