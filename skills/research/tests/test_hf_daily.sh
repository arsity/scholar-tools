#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

echo "Test 1: Fetch daily papers..."
RESULT=$("$SCRIPTS/hf_daily_papers.sh" 5)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT papers"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No papers"
    FAIL=$((FAIL + 1))
fi

echo "Test 2: Papers have required fields..."
HAS=$(echo "$RESULT" | jq -s '.[0] | [has("title"), has("arxiv_id"), has("upvotes")] | all')
if [[ "$HAS" == "true" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "hf_daily: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
