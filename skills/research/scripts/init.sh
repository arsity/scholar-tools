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

# Data directory
export SKILL_DATA_DIR="$SKILL_ROOT/data"

# Rate limit config
export S2_RATE_LIMIT_FILE="/tmp/.s2_rate_limit"
export S2_MIN_INTERVAL="${S2_MIN_INTERVAL:-1}"
export DBLP_RATE_LIMIT_FILE="/tmp/.dblp_rate_limit"
export DBLP_MIN_INTERVAL="${DBLP_MIN_INTERVAL:-1}"

# arXiv citation threshold
export ARXIV_CITATION_THRESHOLD="${ARXIV_CITATION_THRESHOLD:-100}"

# DBLP API hosts — main server + Trier mirror fallback
DBLP_HOSTS=("https://dblp.org" "https://dblp.uni-trier.de")

# Helper: try a DBLP API request, fallback to mirror on server errors
# Usage: dblp_request "/search/publ/api?q=...&format=json&h=10"
# Returns: response body on stdout; sets DBLP_HTTP_CODE
# Falls back to next host on 5xx, 429, timeouts, or HTML error pages
dblp_request() {
    local path="$1"
    for host in "${DBLP_HOSTS[@]}"; do
        rate_limit "$DBLP_RATE_LIMIT_FILE" "$DBLP_MIN_INTERVAL"
        local response
        response=$(curl -sL -w "\n%{http_code}" "${host}${path}" --max-time 30 2>/dev/null) || true
        DBLP_HTTP_CODE=$(echo "$response" | tail -n1)
        # curl transport failure (DNS, timeout, connection refused) → empty/invalid HTTP code
        if [[ -z "$DBLP_HTTP_CODE" ]] || ! [[ "$DBLP_HTTP_CODE" =~ ^[0-9]+$ ]]; then
            continue
        fi
        local body
        body=$(echo "$response" | sed '$d')

        case "$DBLP_HTTP_CODE" in
            200)
                # HTML error pages sometimes come as 200
                if [[ "$body" == *"<!DOCTYPE"* ]] || [[ "$body" == *"<html"* ]]; then
                    continue
                fi
                echo "$body"
                return 0
                ;;
            404)
                # Not found is definitive — don't fallback
                DBLP_HTTP_CODE=404
                return 1
                ;;
            *)
                # 429, 5xx, timeouts, connection errors — try next host
                continue
                ;;
        esac
    done
    # All hosts failed
    return 1
}

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
