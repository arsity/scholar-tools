#!/bin/bash
# DOI to BibTeX via content negotiation
# Usage: bash scripts/doi2bibtex.sh "doi"

set -e

DOI="${1:-}"

if [[ -z "$DOI" ]]; then
    echo '{"error": "Usage: bash scripts/doi2bibtex.sh \"doi\""}' >&2
    exit 1
fi

# Clean DOI (strip URL prefix if present)
DOI=$(echo "$DOI" | sed 's|https://doi.org/||g; s|http://doi.org/||g; s|doi.org/||g; s|^ *||; s| *$||')

RESPONSE=$(curl -sL \
    -H "Accept: text/bibliography; style=bibtex" \
    -H "Accept-Language: en" \
    "https://doi.org/${DOI}" \
    --max-time 30 2>/dev/null)

if [[ -z "$RESPONSE" ]] || [[ "$RESPONSE" == "<!DOCTYPE"* ]]; then
    echo "{\"error\": \"Failed to fetch BibTeX for DOI: $DOI\"}" >&2
    exit 1
fi

echo "$RESPONSE"
