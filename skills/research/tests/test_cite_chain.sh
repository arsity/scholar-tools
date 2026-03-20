#!/bin/bash
# Integration test: full DBLP > CrossRef > S2 citation chain
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: DBLP should find ResNet
echo "Test 1: Cite chain — DBLP finds ResNet..."
DBLP_RESULT=$("$SCRIPTS/dblp_search.sh" "Deep Residual Learning for Image Recognition" 1)
DBLP_TITLE=$(echo "$DBLP_RESULT" | jq -s '.[0]' | jq -r '.title // empty')
if [[ -n "$DBLP_TITLE" ]]; then
    echo "  PASS: Found DBLP title=$DBLP_TITLE"
    PASS=$((PASS + 1))

    sleep 1

    # Fetch condensed BibTeX via search API (with author+year for ranking accuracy)
    BIB=$("$SCRIPTS/dblp_bibtex.sh" "Deep Residual Learning for Image Recognition" "He" "2016")
    if echo "$BIB" | grep -q "@"; then
        echo "  PASS: Got BibTeX via DBLP"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: BibTeX fetch failed"
        FAIL=$((FAIL + 1))
    fi
else
    echo "  FAIL: DBLP did not find paper"
    FAIL=$((FAIL + 1))
    FAIL=$((FAIL + 1))
fi

sleep 1

# Test 2: CrossRef as fallback (use DOI directly)
echo "Test 2: Cite chain — CrossRef DOI fallback..."
BIB_CR=$("$SCRIPTS/doi2bibtex.sh" "10.1109/CVPR.2016.90")
if echo "$BIB_CR" | grep -q "He"; then
    echo "  PASS: Got BibTeX via CrossRef DOI"
    PASS=$((PASS + 1))
else
    echo "  FAIL: CrossRef DOI fallback failed"
    FAIL=$((FAIL + 1))
fi

sleep 1

# Test 3: S2 match as last resort
echo "Test 3: Cite chain — S2 title match fallback..."
S2_RESULT=$("$SCRIPTS/s2_match.sh" "Deep Residual Learning for Image Recognition")
S2_TITLE=$(echo "$S2_RESULT" | jq -s '.[0] | .title' -r)
if [[ -n "$S2_TITLE" && "$S2_TITLE" != "null" ]]; then
    echo "  PASS: S2 matched title=$S2_TITLE"
    PASS=$((PASS + 1))
else
    echo "  FAIL: S2 match failed"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "cite_chain: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
