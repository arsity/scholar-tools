#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../skills/research/scripts"
PASS=0; FAIL=0

# Test 1: CCF lookup for CVPR
echo "Test 1: CCF lookup for CVPR..."
RESULT=$("$SCRIPTS/ccf_lookup.sh" "CVPR")
if echo "$RESULT" | jq -e '.rank' > /dev/null 2>&1; then
    echo "  PASS: CCF rank found"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No CCF rank"
    FAIL=$((FAIL + 1))
fi

# Test 2: IF lookup for a known journal
echo "Test 2: IF lookup..."
RESULT=$("$SCRIPTS/if_lookup.sh" "Nature")
if echo "$RESULT" | jq -e '.factor' > /dev/null 2>&1; then
    echo "  PASS: IF found"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No IF"
    FAIL=$((FAIL + 1))
fi

# Test 3: Venue info returns summary
echo "Test 3: Venue info for CVPR..."
RESULT=$("$SCRIPTS/venue_info.sh" "CVPR")
if echo "$RESULT" | jq -e '.summary' > /dev/null 2>&1; then
    echo "  PASS: Summary present"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No summary"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "quality_eval: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
