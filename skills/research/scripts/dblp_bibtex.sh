#!/bin/bash
# DBLP BibTeX fetch — condensed format via official search API
# Usage: bash scripts/dblp_bibtex.sh "paper title" [first_author] [year]
#
# Adding first_author and/or year dramatically improves ranking accuracy.
# Without them, the search may return a different paper as the top result.
# Falls back to dblp.uni-trier.de if dblp.org is unavailable.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

TITLE="${1:-}"
AUTHOR="${2:-}"
YEAR="${3:-}"

if [[ -z "$TITLE" ]]; then
    echo '{"error": "Usage: bash scripts/dblp_bibtex.sh \"paper title\" [first_author] [year]"}' >&2
    exit 1
fi

# Build query: title + optional author/year constraints
QUERY="$TITLE"
[[ -n "$AUTHOR" ]] && QUERY="$QUERY author:${AUTHOR}"
[[ -n "$YEAR" ]] && QUERY="$QUERY year:${YEAR}"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)

BODY=$(dblp_request "/search/publ/api?q=${ENCODED_QUERY}&format=bib0&h=1") || {
    echo "{\"error\": \"DBLP BibTeX unavailable (all hosts failed) for query: $TITLE\"}" >&2
    exit 1
}

if [[ -z "$BODY" ]]; then
    echo "{\"error\": \"DBLP BibTeX not found for query: $TITLE\"}" >&2
    exit 1
fi

echo "$BODY"
