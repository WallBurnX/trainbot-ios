#!/usr/bin/env bash
# Attach a real domain to the TrainBot CRM on the VPS.
#
# The VPS terminates TLS in nginx behind an SNI stream router
# (/etc/nginx/stream.d/nl-sni-router.conf): port 443 is shared with the VPN
# services, so every HTTPS host name must be mapped to its own loopback port.
# This script:
#   1. adds the domain to the SNI router (loopback port 8445, same as sslip.io);
#   2. adds the domain to the HTTP/ACME + HTTPS server blocks of the trainbot site;
#   3. issues a Let's Encrypt certificate via webroot (or extends the existing one);
#   4. updates ALLOWED_ORIGINS in /opt/trainbot/.env and restarts the container.
#
# Run ON THE VPS as root after the DNS A/AAAA record points to 178.173.250.250:
#   bash /opt/trainbot/scripts/setup-domain.sh train.example.com [--staging] [--dry-run]
set -Eeuo pipefail

DOMAIN="${1:-}"
STAGING=""
DRY_RUN=""
for arg in "${@:2}"; do
    case "$arg" in
        --staging) STAGING="--test-cert" ;;
        --dry-run) DRY_RUN="1" ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
if [[ -z "$DOMAIN" || ! "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
    echo "Usage: $0 <domain> [--staging] [--dry-run]" >&2
    exit 2
fi

PROJECT_DIR="${PROJECT_DIR:-/opt/trainbot}"
SITE_CONF="/etc/nginx/sites-available/trainbot"
SNI_CONF="/etc/nginx/stream.d/nl-sni-router.conf"
ACME_ROOT="/var/www/trainbot-acme"
LEGACY_HOST="train.178-173-250-250.sslip.io"
LOOPBACK_PORT="8445"
VPS_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

echo "[1/6] Checking DNS for $DOMAIN"
# Ask the zone's authoritative name server first: local resolvers may still
# cache a parking/wildcard answer for hours after the record is created.
APEX="$(printf '%s' "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')"
AUTH_NS="$(dig +short +time=3 +tries=1 NS "$APEX" 2>/dev/null | head -1 || true)"
RESOLVED=""
if [[ -n "$AUTH_NS" ]]; then
    RESOLVED="$(dig +short +time=3 +tries=1 A "$DOMAIN" "@$AUTH_NS" 2>/dev/null | grep -E '^[0-9.]+$' | sort -u | tr '\n' ' ' || true)"
fi
if [[ -z "$RESOLVED" ]]; then
    RESOLVED="$(getent ahostsv4 "$DOMAIN" | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
fi
if [[ -z "$RESOLVED" ]]; then
    echo "DNS for $DOMAIN does not resolve yet. Create an A record → $VPS_IP and retry." >&2
    exit 1
fi
if [[ "$RESOLVED" != *"$VPS_IP"* ]]; then
    echo "WARNING: $DOMAIN resolves to [$RESOLVED], this server is $VPS_IP. Let's Encrypt will fail until DNS propagates." >&2
    [[ -n "$DRY_RUN" ]] || exit 1
fi
echo "DNS OK: $DOMAIN → $RESOLVED"

run() {
    if [[ -n "$DRY_RUN" ]]; then
        echo "DRY-RUN: $*"
    else
        "$@"
    fi
}

echo "[2/6] Mapping $DOMAIN in the SNI stream router"
if ! grep -qE "^\s*${DOMAIN//./\\.}\s+" "$SNI_CONF"; then
    run cp -a "$SNI_CONF" "$SNI_CONF.bak.$(date +%Y%m%d_%H%M%S)"
    if [[ -z "$DRY_RUN" ]]; then
        sed -i "/^\s*${LEGACY_HOST//./\\.}\s\+127\.0\.0\.1:${LOOPBACK_PORT};/a\\    ${DOMAIN} 127.0.0.1:${LOOPBACK_PORT};" "$SNI_CONF"
    fi
    echo "Added ${DOMAIN} → 127.0.0.1:${LOOPBACK_PORT}"
else
    echo "Already mapped."
fi

echo "[3/6] Adding $DOMAIN to nginx server blocks"
if ! grep -qE "server_name .*\b${DOMAIN//./\\.}\b" "$SITE_CONF"; then
    run cp -a "$SITE_CONF" "$SITE_CONF.bak.$(date +%Y%m%d_%H%M%S)"
    if [[ -z "$DRY_RUN" ]]; then
        sed -i "s/^\(\s*server_name\s\+${LEGACY_HOST//./\\.}\)\(.*\);/\1 ${DOMAIN}\2;/" "$SITE_CONF"
    fi
    echo "server_name now includes ${DOMAIN}"
else
    echo "Already present."
fi
run mkdir -p "$ACME_ROOT"
run nginx -t
run systemctl reload nginx

echo "[4/6] Requesting certificate"
# One certificate covers both the legacy sslip.io host and the new domain, so
# the existing HTTPS block keeps working during the switch.
run certbot certonly --webroot -w "$ACME_ROOT" \
    --cert-name "$LEGACY_HOST" --expand \
    -d "$LEGACY_HOST" -d "$DOMAIN" \
    --non-interactive --agree-tos --keep-until-expiring $STAGING
run nginx -t
run systemctl reload nginx

echo "[5/6] Updating ALLOWED_ORIGINS and restarting the container"
ENV_FILE="$PROJECT_DIR/.env"
if [[ -z "$DRY_RUN" ]]; then
    if grep -q '^ALLOWED_ORIGINS=' "$ENV_FILE"; then
        current="$(grep '^ALLOWED_ORIGINS=' "$ENV_FILE" | cut -d= -f2-)"
        if [[ ",$current," != *",https://$DOMAIN,"* ]]; then
            sed -i "s|^ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=${current},https://${DOMAIN}|" "$ENV_FILE"
        fi
    else
        echo "ALLOWED_ORIGINS=https://${LEGACY_HOST},https://${DOMAIN}" >> "$ENV_FILE"
    fi
    if grep -q '^TRAINBOT_SITE_ADDRESS=' "$ENV_FILE"; then
        sed -i "s|^TRAINBOT_SITE_ADDRESS=.*|TRAINBOT_SITE_ADDRESS=${DOMAIN}|" "$ENV_FILE"
    else
        echo "TRAINBOT_SITE_ADDRESS=${DOMAIN}" >> "$ENV_FILE"
    fi
    (cd "$PROJECT_DIR" && docker compose up -d --no-build --force-recreate crm)
else
    echo "DRY-RUN: would append https://${DOMAIN} to ALLOWED_ORIGINS and recreate the container"
fi

echo "[6/6] Verifying"
if [[ -z "$DRY_RUN" ]]; then
    for attempt in $(seq 1 20); do
        # --resolve bypasses a local resolver that may still cache the old address.
        if curl -fsS --max-time 5 --resolve "${DOMAIN}:443:${VPS_IP}" "https://${DOMAIN}/api/health" >/dev/null 2>&1; then
            curl -fsS --resolve "${DOMAIN}:443:${VPS_IP}" "https://${DOMAIN}/api/health"; echo
            echo "Done: https://${DOMAIN}/"
            exit 0
        fi
        sleep 3
    done
    echo "Health check over https://${DOMAIN} did not succeed; inspect: curl -vk https://${DOMAIN}/api/health" >&2
    exit 1
fi
echo "DRY-RUN complete."
