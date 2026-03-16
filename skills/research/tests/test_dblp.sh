#!/bin/bash
# Test DBLP search and BibTeX fetch
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: Search for ResNet
echo "Test 1: DBLP search for 'Deep Residual Learning'..."
RESULT=$("$SCRIPTS/dblp_search.sh" "Deep Residual Learning for Image Recognition" 3)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No results"
    FAIL=$((FAIL + 1))
fi

# Test 2: Result has dblp_key
echo "Test 2: Result has dblp_key..."
KEY=$(echo "$RESULT" | jq -s ".[0]" | jq -r '.dblp_key // empty')
if [[ -n "$KEY" ]]; then
    echo "  PASS: dblp_key=$KEY"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No dblp_key"
    FAIL=$((FAIL + 1))
fi

sleep 1

# Test 3: Fetch BibTeX for known key
echo "Test 3: Fetch BibTeX for conf/cvpr/HeZRS16..."
BIB=$("$SCRIPTS/dblp_bibtex.sh" "conf/cvpr/HeZRS16")
if echo "$BIB" | grep -q "@inproceedings"; then
    echo "  PASS: Got valid BibTeX"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Invalid BibTeX"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "dblp: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
