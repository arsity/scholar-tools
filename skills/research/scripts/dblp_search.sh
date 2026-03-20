#!/bin/bash
# DBLP publication search
# Usage: bash scripts/dblp_search.sh "query" [limit]
# Falls back to dblp.uni-trier.de if dblp.org is unavailable.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-10}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/dblp_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)

BODY=$(dblp_request "/search/publ/api?q=${ENCODED_QUERY}&format=json&h=${LIMIT}") || {
    echo "{\"error\": \"DBLP unavailable (all hosts failed)\"}" >&2
    exit 1
}

TOTAL=$(echo "$BODY" | jq -r '.result.hits["@total"] // "0"')
if [[ "$TOTAL" == "0" ]]; then
    echo '{"info": "No DBLP results found"}' >&2
else
    echo "$BODY" | jq '.result.hits.hit[]? | {
        dblp_key: .info.key,
        title: .info.title,
        year: (.info.year | tonumber? // null),
        venue: .info.venue,
        authors: (if .info.authors.author | type == "array" then
            [.info.authors.author[]? | .text][:3]
        else
            [.info.authors.author.text // "N/A"]
        end),
        doi: .info.doi,
        url: .info.url,
        source: "dblp"
    }'
fi
