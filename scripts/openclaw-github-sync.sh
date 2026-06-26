#!/usr/bin/env bash
# =============================================================================
# openclaw-github-sync.sh
# Idempotent Git backup daemon for OpenClaw configs, OpenCode artifacts,
# custom extensions, and .learnings/ logs.
#
# Auth: GITHUB_TOKEN env var (PAT) or SSH key (~/.ssh/id_ed25519)
# Schedule: systemd timer (recommended every 6h) or manual invocation
# Logs:    .learnings/ERRORS.md (failures only)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME}"
GIT_REMOTE_NAME="${GIT_REMOTE_NAME:-origin}"
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REMOTE_URL="${GIT_REMOTE_URL:-}"
LEARNINGS_DIR="${LEARNINGS_DIR:-$HOME/.learnings}"
ERRORS_FILE="${ERRORS_FILE:-$LEARNINGS_DIR/ERRORS.md}"
LOCK_FILE="${LOCK_FILE:-/tmp/openclaw-github-sync.lock}"
LOG_FILE="${LOG_FILE:-$HOME/logs/github-sync.log}"
DRY_RUN="${DRY_RUN:-false}"
AUTH_METHOD="unknown"

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
setup_environment() {
    mkdir -p "$LEARNINGS_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"

    if [[ "${SYNC_LOG_TO_FILE:-true}" == "true" ]]; then
        exec 1> >(tee -a "$LOG_FILE") 2>&1
    fi
}

# ---------------------------------------------------------------------------
# Locking (prevent concurrent runs)
# ---------------------------------------------------------------------------
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "[$(date -Iseconds)] WARN: Another sync process (PID $pid) is running. Exiting."
            exit 0
        fi
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# ---------------------------------------------------------------------------
# Git Authentication Setup
# ---------------------------------------------------------------------------
setup_git_auth() {
    if [[ -z "$(git config --global user.name 2>/dev/null || echo '')" ]]; then
        git config --global user.name "openclaw-github-sync"
    fi
    if [[ -z "$(git config --global user.email 2>/dev/null || echo '')" ]]; then
        git config --global user.email "sync@openclaw.local"
    fi

    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "[$(date -Iseconds)] INFO: Using GITHUB_TOKEN for authentication"
        if [[ -n "$GIT_REMOTE_URL" ]] && [[ "$GIT_REMOTE_URL" == https://github.com/* ]]; then
            local clean_url="${GIT_REMOTE_URL#https://}"
            GIT_REMOTE_URL="https://${GITHUB_TOKEN}@${clean_url}"
        fi
        AUTH_METHOD="token"
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        echo "[$(date -Iseconds)] INFO: Using GH_TOKEN for authentication"
        export GITHUB_TOKEN="$GH_TOKEN"
        if [[ -n "$GIT_REMOTE_URL" ]] && [[ "$GIT_REMOTE_URL" == https://github.com/* ]]; then
            local clean_url="${GIT_REMOTE_URL#https://}"
            GIT_REMOTE_URL="https://${GH_TOKEN}@${clean_url}"
        fi
        AUTH_METHOD="token"
    elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        echo "[$(date -Iseconds)] INFO: Using SSH key (~/.ssh/id_ed25519)"
        export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"
        AUTH_METHOD="ssh"
    elif [[ -f "$HOME/.ssh/id_rsa" ]]; then
        echo "[$(date -Iseconds)] INFO: Using SSH key (~/.ssh/id_rsa)"
        export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/id_rsa -o StrictHostKeyChecking=accept-new"
        AUTH_METHOD="ssh"
    else
        log_error "AUTH_FAILURE" "No GITHUB_TOKEN, GH_TOKEN, or SSH key found."
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Git Remote Management
# ---------------------------------------------------------------------------
ensure_remote() {
    if [[ -z "$GIT_REMOTE_URL" ]]; then
        log_error "CONFIG_MISSING" "GIT_REMOTE_URL is not set."
        exit 1
    fi

    local current_url
    current_url=$(git -C "$WORKSPACE_DIR" remote get-url "$GIT_REMOTE_NAME" 2>/dev/null || echo "")

    if [[ -z "$current_url" ]]; then
        git -C "$WORKSPACE_DIR" remote add "$GIT_REMOTE_NAME" "$GIT_REMOTE_URL"
        echo "[$(date -Iseconds)] INFO: Added remote '$GIT_REMOTE_NAME' -> $GIT_REMOTE_URL"
    elif [[ "$current_url" != "$GIT_REMOTE_URL" ]]; then
        git -C "$WORKSPACE_DIR" remote set-url "$GIT_REMOTE_NAME" "$GIT_REMOTE_URL"
        echo "[$(date -Iseconds)] INFO: Updated remote '$GIT_REMOTE_NAME' URL"
    fi
}

# ---------------------------------------------------------------------------
# Error Logging (.learnings/ERRORS.md structured format)
# ---------------------------------------------------------------------------
log_error() {
    local error_type="$1"
    local error_message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "[$timestamp] ERROR [$error_type]: $error_message" >&2

    local host_short
    host_short=$(hostname -s 2>/dev/null || echo "unknown")

    cat >> "$ERRORS_FILE" <<ERRBLOCK

## [ERR-${timestamp}] ${error_type}

**Logged**: ${timestamp}
**Priority**: high
**Status**: unresolved
**Area**: github-sync

### Summary
Automated sync failure: ${error_message}

### Details
- **Error Type**: ${error_type}
- **Host**: ${host_short}
- **Auth Method**: ${AUTH_METHOD:-unknown}
- **Workspace**: ${WORKSPACE_DIR}
- **Remote**: ${GIT_REMOTE_URL:-unset}

### Suggested Action
1. Verify network connectivity to GitHub
2. Check authentication (GITHUB_TOKEN or SSH key validity)
3. Check for merge conflicts: \`cd ${WORKSPACE_DIR} && git status\`
4. Verify remote URL: \`git remote -v\`
5. Run manually: \`${0}\` to test

### Metadata
- Source: openclaw-github-sync
- Tags: github, sync, ${error_type,,}
- Pattern-Key: github.sync.${error_type,,}

---
ERRBLOCK

    echo "[$timestamp] ERROR: Logged to $ERRORS_FILE"
}

# ---------------------------------------------------------------------------
# Core Sync Logic
# ---------------------------------------------------------------------------
perform_sync() {
    echo "[$(date -Iseconds)] INFO: Starting sync cycle"

    cd "$WORKSPACE_DIR"

    local paths_to_add=(
        ".gitignore"
        ".openclaw/"
        ".opencode/"
        ".claude/"
        "openclaw-workspace/"
        "scripts/"
        "lockin-labs-office/"
        "assets/"
        "omo.config.json"
        "opencode.json"
        "skills-lock.json"
        ".gitconfig"
        ".npmrc"
    )

    local staged_any=false
    for path in "${paths_to_add[@]}"; do
        if [[ -e "$WORKSPACE_DIR/$path" ]]; then
            git add --all -- "$path" 2>/dev/null || true
            staged_any=true
        fi
    done

    while IFS= read -r -d '' learnings_dir; do
        git add --all -- "$learnings_dir" 2>/dev/null || true
        staged_any=true
    done < <(find "$WORKSPACE_DIR" -type d -name ".learnings" -not -path "*/node_modules/*" -not -path "*/.git/*" -print0 2>/dev/null || true)

    if [[ "$staged_any" == "false" ]]; then
        echo "[$(date -Iseconds)] INFO: No paths to stage. Nothing to commit."
        return 0
    fi

    if git diff --cached --quiet 2>/dev/null; then
        echo "[$(date -Iseconds)] INFO: No changes to commit."
        return 0
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local hostname_short
    hostname_short=$(hostname -s 2>/dev/null || echo "unknown")
    local commit_msg
    commit_msg="[auto-sync] ${timestamp} @ ${hostname_short} — automated backup of OpenClaw/OpenCode configs, extensions, and learnings"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[$(date -Iseconds)] DRY-RUN: Would commit and push to $GIT_REMOTE_NAME/$GIT_BRANCH"
        echo "  Message: $commit_msg"
        return 0
    fi

    if ! git commit -m "$commit_msg" --no-verify; then
        log_error "COMMIT_FAILURE" "git commit failed. Check for conflicts or index issues."
        return 1
    fi

    echo "[$(date -Iseconds)] INFO: Committed successfully"

    local push_output
    if push_output=$(git push "$GIT_REMOTE_NAME" "$GIT_BRANCH" 2>&1); then
        echo "[$(date -Iseconds)] INFO: Push successful"
    else
        log_error "PUSH_FAILURE" "git push failed: ${push_output//$'\n'/ }"
        return 1
    fi

    echo "[$(date -Iseconds)] INFO: Sync cycle complete"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    setup_environment
    acquire_lock
    trap release_lock EXIT INT TERM

    setup_git_auth
    ensure_remote
    perform_sync || true

    echo "[$(date -Iseconds)] INFO: openclaw-github-sync finished"
}

main "$@"
