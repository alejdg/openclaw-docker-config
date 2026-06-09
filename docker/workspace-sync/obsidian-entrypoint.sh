#!/bin/bash
set -euo pipefail

# If repo is not configured, idle forever (don't restart-loop)
if [[ -z "${GIT_OBSIDIAN_REPO:-}" ]] && [[ -z "${GIT_OBSIDIAN_REMOTE:-}" ]]; then
    echo "[obsidian-sync] GIT_OBSIDIAN_REPO and GIT_OBSIDIAN_REMOTE not set — idling"
    exec sleep infinity
fi

VAULT_DIR="${VAULT_DIR:-/vault}"
if [[ "$VAULT_DIR" == "/" ]]; then
    echo "[obsidian-sync] VAULT_DIR cannot be /"
    exit 1
fi

git config --global --add safe.directory "$VAULT_DIR"

SCHEDULE="${OBSIDIAN_SYNC_SCHEDULE:-0 4 * * *}"

if [[ -n "$GIT_OBSIDIAN_REPO" ]]; then
    echo "[obsidian-sync] Repo: $GIT_OBSIDIAN_REPO"
fi
if [[ -n "$GIT_OBSIDIAN_REMOTE" ]]; then
    echo "[obsidian-sync] Remote: VARIABLE_HIDDEN_FOR_SECURITY"
fi
echo "[obsidian-sync] Branch: ${GIT_OBSIDIAN_BRANCH:-main}"
echo "[obsidian-sync] Schedule: $SCHEDULE"
echo ""

# Run initial sync to verify credentials
echo "[obsidian-sync] Running initial sync..."
/usr/local/bin/obsidian-sync.sh

# Set up cron — pass env vars through to the cron job
export -p > /tmp/env.sh
chmod 600 /tmp/env.sh

cat > /usr/local/bin/run-obsidian-sync.sh << 'WRAPPER'
#!/bin/bash
. /tmp/env.sh
exec /usr/local/bin/obsidian-sync.sh
WRAPPER
chmod +x /usr/local/bin/run-obsidian-sync.sh

echo "$SCHEDULE run-one /usr/local/bin/run-obsidian-sync.sh >> /proc/1/fd/1 2>> /proc/1/fd/2" > /etc/crontabs/root

echo "[obsidian-sync] Cron configured, starting scheduler..."
exec crond -f -l 2
