#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../skills/research/scripts"
PASS=0; FAIL=0

# Test 1: s2_search returns results
echo "Test 1: s2_search for 'human pose estimation'..."
RESULT=$("$SCRIPTS/s2_search.sh" "human pose estimation" 5)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No results"
    FAIL=$((FAIL + 1))
fi

# Test 2: Results have required fields
echo "Test 2: Required fields present..."
HAS=$(echo "$RESULT" | jq -s '.[0] | [has("paper_id"), has("title"), has("citations"), has("source")] | all')
if [[ "$HAS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# Test 3: Source field is "s2"
echo "Test 3: Source is s2..."
SRC=$(echo "$RESULT" | jq -s '.[0] | .source' -r)
if [[ "$SRC" == "s2" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL: source=$SRC"
    FAIL=$((FAIL + 1))
fi

sleep 2

# Test 4: s2_bulk_search returns results with year filter
echo "Test 4: s2_bulk_search with year filter..."
RESULT=$("$SCRIPTS/s2_bulk_search.sh" "human pose estimation" "2023-" 5)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No results"
    FAIL=$((FAIL + 1))
fi

# Test 5: No arguments should fail
echo "Test 5: No arguments should error..."
if ! "$SCRIPTS/s2_search.sh" 2>/dev/null; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "s2_search: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
