#!/bin/bash
# Test s2_citations.sh and s2_references.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# ResNet paper ID
RESNET_ID="649def34f8be52c8b66281af98ae884c09aef38b"

# Test 1: Citations returns results
echo "Test 1: s2_citations returns results..."
CIT_RESULT=$("$SCRIPTS/s2_citations.sh" "$RESNET_ID" 5)
CIT_COUNT=$(echo "$CIT_RESULT" | jq -s 'length')
if [[ "$CIT_COUNT" -gt 0 ]]; then
    echo "  PASS: Got $CIT_COUNT citing papers"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No citations returned"
    FAIL=$((FAIL + 1))
fi

sleep 1

# Test 2: References returns results
echo "Test 2: s2_references returns results..."
REF_RESULT=$("$SCRIPTS/s2_references.sh" "$RESNET_ID" 5)
REF_COUNT=$(echo "$REF_RESULT" | jq -s 'length')
if [[ "$REF_COUNT" -gt 0 ]]; then
    echo "  PASS: Got $REF_COUNT referenced papers"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No references returned"
    FAIL=$((FAIL + 1))
fi

# Test 3: Citations have required fields
echo "Test 3: Citation results have required fields..."
HAS_FIELDS=$(echo "$CIT_RESULT" | jq -s '.[0] | [has("paper_id"), has("title"), has("citations")] | all')
if [[ "$HAS_FIELDS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "s2_network: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
