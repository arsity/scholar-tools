#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../skills/research/scripts"
PASS=0; FAIL=0

# Test 1: CrossRef search returns results
echo "Test 1: CrossRef search..."
RESULT=$("$SCRIPTS/crossref_search.sh" "deep residual learning" 3)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No results"
    FAIL=$((FAIL + 1))
fi

# Test 2: Results have DOI
echo "Test 2: Results have DOI..."
DOI=$(echo "$RESULT" | jq -s ".[0]" | jq -r '.doi // empty')
if [[ -n "$DOI" ]]; then
    echo "  PASS: doi=$DOI"
    PASS=$((PASS + 1))
else
    echo "  FAIL: No DOI"
    FAIL=$((FAIL + 1))
fi

# Test 3: doi2bibtex returns valid BibTeX
echo "Test 3: doi2bibtex..."
BIB=$("$SCRIPTS/doi2bibtex.sh" "10.1109/CVPR.2016.90")
if echo "$BIB" | grep -q "@"; then
    echo "  PASS: Valid BibTeX"
    PASS=$((PASS + 1))
else
    echo "  FAIL: Invalid BibTeX"
    FAIL=$((FAIL + 1))
fi

# Test 4: doi2bibtex with no args should fail
echo "Test 4: No args should error..."
if ! "$SCRIPTS/doi2bibtex.sh" 2>/dev/null; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL"
    FAIL=$((FAIL + 1))
fi

# Test 5: et al. appended for papers with >3 authors (ResNet has 4: He, Zhang, Ren, Sun)
echo "Test 5: et al. for >3 authors..."
RESNET=$("$SCRIPTS/crossref_search.sh" "deep residual learning image recognition" 3)
ET_AL=$(echo "$RESNET" | jq -s '[.[].authors | contains("et al.")] | any')
if [[ "$ET_AL" == "true" ]]; then
    echo "  PASS: et al. present"
    PASS=$((PASS + 1))
else
    echo "  FAIL: et al. missing for >3 author paper"
    FAIL=$((FAIL + 1))
fi

# Test 6: authors field is never null/empty
echo "Test 6: authors never null..."
FIRST_RESULT=$("$SCRIPTS/crossref_search.sh" "attention mechanism" 3)
NULL_AUTHORS=$(echo "$FIRST_RESULT" | jq -s '[.[].authors | (. == null or length == 0)] | any')
if [[ "$NULL_AUTHORS" == "false" ]]; then
    echo "  PASS"
    PASS=$((PASS + 1))
else
    echo "  FAIL: some authors null or empty"
    FAIL=$((FAIL + 1))
fi

echo "---"
echo "crossref: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
