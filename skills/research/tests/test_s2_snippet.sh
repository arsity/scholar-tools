#!/bin/bash
# Tests for s2_snippet.sh — verifies correct field mapping against actual API response

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

check() {
    local desc="$1" result="$2" expected="$3"
    if [[ "$result" == "$expected" ]]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (got: '$result', expected: '$expected')"
        FAIL=$((FAIL + 1))
    fi
}

echo "Test 1: Returns results for a valid query..."
RESULT=$(bash "$SCRIPTS/s2_snippet.sh" "pose estimation" 3 2>/dev/null)
COUNT=$(echo "$RESULT" | jq -s 'length' 2>/dev/null || echo 0)
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT snippets"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No results"
    FAIL=$((FAIL + 1))
fi

echo "Test 2: paper_id is non-null..."
HAS_ID=$(echo "$RESULT" | jq -s '.[0].paper_id != null' 2>/dev/null)
check "paper_id populated" "$HAS_ID" "true"

echo "Test 3: title is non-null..."
HAS_TITLE=$(echo "$RESULT" | jq -s '.[0].title != null' 2>/dev/null)
check "title populated" "$HAS_TITLE" "true"

echo "Test 4: snippet text is non-empty..."
SNIPPET_LEN=$(echo "$RESULT" | jq -s '.[0].snippet | length' 2>/dev/null || echo 0)
if [[ "$SNIPPET_LEN" -gt 20 ]]; then
    echo "  PASS: snippet length $SNIPPET_LEN"
    PASS=$((PASS + 1))
else
    echo "  FAIL: snippet too short or null ($SNIPPET_LEN)"
    FAIL=$((FAIL + 1))
fi

echo "Test 5: snippet_section is a string (not null)..."
SECTION=$(echo "$RESULT" | jq -s '.[0].snippet_section | type' 2>/dev/null)
check "snippet_section is string" "$SECTION" '"string"'

echo "Test 6: authors is an array..."
AUTHORS_TYPE=$(echo "$RESULT" | jq -s '.[0].authors | type' 2>/dev/null)
check "authors is array" "$AUTHORS_TYPE" '"array"'

echo "---"
echo "s2_snippet: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
