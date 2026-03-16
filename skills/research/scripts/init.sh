#!/bin/bash
# Initialize environment — load config and set path variables
# Usage: source scripts/init.sh

# Determine skill root directory
if [[ -n "${CLAUDE_SKILL_ROOT:-}" ]]; then
    SKILL_ROOT="${CLAUDE_SKILL_ROOT}"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
fi

# Load .env if present
if [[ -f "$SKILL_ROOT/.env" ]]; then
    set -a
    source "$SKILL_ROOT/.env"
    set +a
fi

# Data directory
export SKILL_DATA_DIR="$SKILL_ROOT/data"

# Rate limit config
export S2_RATE_LIMIT_FILE="/tmp/.s2_rate_limit"
export S2_MIN_INTERVAL="${S2_MIN_INTERVAL:-1}"
export DBLP_RATE_LIMIT_FILE="/tmp/.dblp_rate_limit"
export DBLP_MIN_INTERVAL="${DBLP_MIN_INTERVAL:-1}"

# arXiv citation threshold
export ARXIV_CITATION_THRESHOLD="${ARXIV_CITATION_THRESHOLD:-100}"

# Helper: enforce rate limit for a given service
# Usage: rate_limit "$RATE_LIMIT_FILE" "$MIN_INTERVAL"
rate_limit() {
    local file="$1"
    local interval="$2"
    if [[ -f "$file" ]]; then
        local last_time
        last_time=$(cat "$file" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - last_time))
        if [[ $elapsed -lt $interval ]]; then
            sleep $((interval - elapsed))
        fi
    fi
    date +%s > "$file"
}
