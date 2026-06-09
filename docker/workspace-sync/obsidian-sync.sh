
#!/bin/bash
# =============================================================================
# Obsidian Vault Git Sync
# =============================================================================
# Syncs (pushes and pulls) an Obsidian vault to/from a remote git repository.
# Reads config from environment variables (passed by Docker).
# =============================================================================

set -euo pipefail

VAULT_DIR="/vault"

GIT_OBSIDIAN_REPO="${GIT_OBSIDIAN_REPO:-}"
GIT_OBSIDIAN_REMOTE="${GIT_OBSIDIAN_REMOTE:-}"
GIT_OBSIDIAN_BRANCH="${GIT_OBSIDIAN_BRANCH:-main}"
GIT_OBSIDIAN_TOKEN="${GIT_OBSIDIAN_TOKEN:-}"
SYNC_MODE="${OBSIDIAN_SYNC_MODE:-sync}" # sync, push, or pull

# -----------------------------------------------------------------------------
# Validate
# -----------------------------------------------------------------------------

if [[ -z "$GIT_OBSIDIAN_REPO" ]] && [[ -z "$GIT_OBSIDIAN_REMOTE" ]]; then
    echo "[SKIP] Neither GIT_OBSIDIAN_REPO nor GIT_OBSIDIAN_REMOTE set"
    exit 0
fi

if [[ -n "$GIT_OBSIDIAN_REMOTE" ]] && [[ -n "$GIT_OBSIDIAN_REPO" ]]; then
    echo "[SKIP] Both GIT_OBSIDIAN_REMOTE and GIT_OBSIDIAN_REPO are set - please set only one"
    exit 0
fi

if [[ -n "$GIT_OBSIDIAN_REPO" ]] && [[ -z "$GIT_OBSIDIAN_TOKEN" ]]; then
    echo "[ERROR] GIT_OBSIDIAN_TOKEN not set"
    exit 1
fi

if [[ ! -d "$VAULT_DIR" ]]; then
    echo "[SKIP] Vault directory $VAULT_DIR does not exist"
    exit 0
fi

# -----------------------------------------------------------------------------
# Git setup
# -----------------------------------------------------------------------------

if [[ -n "$GIT_OBSIDIAN_REPO" ]]; then
    GIT_OBSIDIAN_REMOTE="https://github.com/${GIT_OBSIDIAN_REPO}.git"
    export GIT_ASKPASS="/usr/local/bin/git-askpass.sh"
    export GIT_TERMINAL_PROMPT=0
fi

# git-askpass.sh reads GIT_WORKSPACE_TOKEN; map our token to that name
export GIT_WORKSPACE_TOKEN="$GIT_OBSIDIAN_TOKEN"

echo "=== Obsidian Vault Sync ==="
if [[ -n "$GIT_OBSIDIAN_REPO" ]]; then
    echo "Repo: $GIT_OBSIDIAN_REPO"
fi
if [[ -n "$GIT_OBSIDIAN_REMOTE" ]]; then
    echo "Remote: VARIABLE_HIDDEN_FOR_SECURITY"
fi
echo "Branch: $GIT_OBSIDIAN_BRANCH"
echo "Mode: $SYNC_MODE"
echo ""

cd "$VAULT_DIR"

if [[ ! -d ".git" ]]; then
    echo "[...] Initializing git repository..."
    git init -b "$GIT_OBSIDIAN_BRANCH" --quiet
fi

if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$GIT_OBSIDIAN_REMOTE"
else
    git remote add origin "$GIT_OBSIDIAN_REMOTE"
fi

git config user.name "Obsidian Sync Bot"
git config user.email "obsidian-sync@noreply.local"

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
if [[ -n "$CURRENT_BRANCH" && "$CURRENT_BRANCH" != "$GIT_OBSIDIAN_BRANCH" ]]; then
    git branch -m "$CURRENT_BRANCH" "$GIT_OBSIDIAN_BRANCH" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Sync logic
# -----------------------------------------------------------------------------

function do_pull() {
    echo "[PULL] Pulling from remote..."
    if ! git fetch origin "$GIT_OBSIDIAN_BRANCH" 2>/dev/null; then
        echo "[WARN] Fetch failed, skipping pull"
        return
    fi

    # Merge remote into local; on any textual conflict prefer the remote side (-X theirs)
    # so the sync always completes without leaving an unfinished rebase/merge state.
    if ! git merge origin/"$GIT_OBSIDIAN_BRANCH" \
            --allow-unrelated-histories \
            -X theirs \
            -m "obsidian sync merge" \
            --quiet 2>&1; then
        echo "[WARN] Merge could not complete, skipping pull step"
    fi

    chown -R "1000:1000" .
    echo "[OK] Vault pulled successfully"
}

function do_push() {
    echo "[PUSH] Checking for changes..."
    find "$VAULT_DIR" -mindepth 2 -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
    git add -A

    REMOTE_BRANCH_EXISTS=0
    if git ls-remote --exit-code origin "$GIT_OBSIDIAN_BRANCH" &>/dev/null; then
        REMOTE_BRANCH_EXISTS=1
        git fetch origin "$GIT_OBSIDIAN_BRANCH" --quiet || true
    fi

    # Use git status --porcelain instead of git diff --cached, which fails on
    # repos with no commits yet (no HEAD to diff against).
    HAS_STAGED_CHANGES=0
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        HAS_STAGED_CHANGES=1
    fi

    AHEAD_COUNT=0
    if [[ "$REMOTE_BRANCH_EXISTS" -eq 1 ]]; then
        AHEAD_COUNT=$(git rev-list --count "origin/$GIT_OBSIDIAN_BRANCH..HEAD" 2>/dev/null || echo "0")
    fi

    if [[ "$HAS_STAGED_CHANGES" -eq 1 ]]; then
        TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
        FILE_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        echo "[PUSH] Committing $FILE_COUNT changed file(s)..."
        git commit -m "obsidian vault sync $TIMESTAMP" --quiet
    fi

    if [[ "$REMOTE_BRANCH_EXISTS" -eq 0 ]]; then
        echo "[PUSH] Remote branch does not exist yet, pushing local branch..."
        git push -u origin "$GIT_OBSIDIAN_BRANCH" --quiet 2>&1
        echo "[OK] Vault pushed successfully"
        return
    fi

    if [[ "$HAS_STAGED_CHANGES" -eq 1 ]]; then
        echo "[PUSH] Pushing committed changes to ${GIT_OBSIDIAN_REPO:-remote} ($GIT_OBSIDIAN_BRANCH)..."
        git push -u origin "$GIT_OBSIDIAN_BRANCH" --quiet 2>&1
        echo "[OK] Vault pushed successfully"
        return
    fi

    if [[ "$AHEAD_COUNT" -gt 0 ]]; then
        echo "[PUSH] Local branch is ahead by $AHEAD_COUNT commit(s), pushing..."
        git push -u origin "$GIT_OBSIDIAN_BRANCH" --quiet 2>&1
        echo "[OK] Vault pushed successfully"
        return
    fi

    echo "[SKIP] No changes to push"
}

case "$SYNC_MODE" in
    pull)
        do_pull
        ;;
    push)
        do_push
        ;;
    sync|*)
        do_pull
        do_push
        ;;
esac

