#!/bin/bash
# Run all research skill tests
# Usage: bash tests/run_all_tests.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL_PASS=0
TOTAL_FAIL=0
TESTS_RUN=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    test_name=$(basename "$test_file" .sh)
    echo ""
    echo "========================================="
    echo "Running: $test_name"
    echo "========================================="

    if bash "$test_file"; then
        echo "=> $test_name: ALL PASSED"
    else
        echo "=> $test_name: SOME FAILURES"
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))

    # Rate limit between test files
    sleep 2
done

echo ""
echo "========================================="
echo "Test suites run: $TESTS_RUN"
echo "Suites with failures: $TOTAL_FAIL"
echo "========================================="

[[ $TOTAL_FAIL -eq 0 ]]
