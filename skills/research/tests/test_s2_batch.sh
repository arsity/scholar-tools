#!/bin/bash
# Test s2_batch.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: Fetch metadata for known paper IDs (ResNet, BERT)
echo "Test 1: Batch fetch 2 known papers..."
RESULT=$("$SCRIPTS/s2_batch.sh" "649def34f8be52c8b66281af98ae884c09aef38b" "df2b0e26d0599ce3e70df8a9da02e51594e0e992")
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -eq 2 ]]; then
    echo "  PASS: Got $COUNT papers"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Expected 2, got $COUNT"
    FAIL=$((FAIL + 1))
fi

# Test 2: Each result has required fields
echo "Test 2: Results have required fields..."
HAS_FIELDS=$(echo "$RESULT" | jq -s '.[0] | [has("paper_id"), has("title"), has("citations"), has("venue")] | all')
if [[ "$HAS_FIELDS" == "true" ]]; then
    echo "  PASS: Required fields present"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Missing required fields"
    FAIL=$((FAIL + 1))
fi

# Test 3: No arguments should fail
echo "Test 3: No arguments should error..."
if ! "$SCRIPTS/s2_batch.sh" 2>/dev/null; then
    echo "  PASS: Correctly errored on no input"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Should have errored"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "s2_batch: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
