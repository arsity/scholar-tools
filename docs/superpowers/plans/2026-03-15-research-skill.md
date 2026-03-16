# Research Skill Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a unified `/research` skill covering the full academic research lifecycle (discover, triage, read, cite, write, trending) with verified citations, quality evaluation, and multi-source search.

**Architecture:** Orchestrator skill (`SKILL.md`) routes to phase modules (`phases/*.md`). Bash scripts handle all API interactions. Bottom-up build order: scripts → tests → phases → orchestrator. All scripts copied from citation-assistant are self-contained — no external skill dependencies except `tanwei/pua`, `Orchestra-Research AI-Research-SKILLs`, and `humanizer`.

**Tech Stack:** Bash scripts (curl, jq, sqlite3), Claude Code skill system (markdown), MCP integrations (AlphaXiv, HF), persistent JSON workspace.

**Spec:** `docs/superpowers/specs/2026-03-15-research-skill-design.md`

---

## File Structure

```
skills/research/
  SKILL.md                      # Orchestrator
  .env.example                  # Template for API keys
  phases/
    discover.md                 # Search + merge + quality eval
    triage.md                   # Quick screening
    read.md                     # Deep analysis
    cite.md                     # BibTeX generation
    write.md                    # Paper writing (LaTeX/md/Notion)
    trending.md                 # Trending paper digest
  scripts/
    init.sh                     # Env loading, rate limit helpers
    s2_search.sh                # S2 relevance search
    s2_bulk_search.sh           # S2 boolean bulk search
    s2_batch.sh                 # S2 batch metadata (POST, up to 500 IDs)
    s2_citations.sh             # S2 citation traversal
    s2_references.sh            # S2 reference traversal
    s2_recommend.sh             # S2 paper recommendations
    s2_snippet.sh               # S2 snippet search in paper bodies
    s2_match.sh                 # S2 exact title match
    dblp_search.sh              # DBLP publication search
    dblp_bibtex.sh              # DBLP key → .bib
    crossref_search.sh          # CrossRef search
    doi2bibtex.sh               # DOI → BibTeX
    author_info.sh              # S2 author h-index
    venue_info.sh               # Venue quality (CCF + IF + quartile)
    ccf_lookup.sh               # CCF ranking lookup
    if_lookup.sh                # Impact factor lookup
    hf_daily_papers.sh          # HF trending papers
  data/
    ccf_2026.sqlite             # CCF rankings database
    ccf_2026.jsonl              # CCF rankings source
    impact_factor.sqlite3       # Impact factor database
  tests/
    test_s2_search.sh           # Tests for S2 search scripts
    test_s2_network.sh          # Tests for S2 citation/reference/recommend
    test_s2_batch.sh            # Tests for S2 batch
    test_dblp.sh                # Tests for DBLP search + BibTeX
    test_crossref.sh            # Tests for CrossRef + DOI
    test_quality_eval.sh        # Tests for venue/author/CCF/IF scripts
    test_hf_daily.sh            # Tests for HF daily papers
    test_cite_chain.sh          # Integration: full DBLP>CrossRef>S2 chain
    run_all_tests.sh            # Runner for all test files
```

---

## Chunk 1: Foundation — Init, Config, Data, and Copied Scripts

### Task 1: Create skill directory structure and config

**Files:**
- Create: `skills/research/SKILL.md` (placeholder)
- Create: `skills/research/.env.example`
- Create: `skills/research/scripts/` (directory)
- Create: `skills/research/phases/` (directory)
- Create: `skills/research/tests/` (directory)
- Create: `skills/research/data/` (directory)

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p skills/research/{scripts,phases,tests,data}
```

- [ ] **Step 2: Create .env.example**

```bash
cat > skills/research/.env.example << 'EOF'
# Semantic Scholar API Key (required)
# Obtain from: https://www.semanticscholar.org/product/api/api-key
S2_API_KEY=""

# arXiv citation threshold for quality classification (optional, default 100)
ARXIV_CITATION_THRESHOLD=100

# S2 minimum interval between requests in seconds (optional, default 1)
S2_MIN_INTERVAL=1
EOF
```

- [ ] **Step 3: Create placeholder SKILL.md**

```bash
cat > skills/research/SKILL.md << 'EOF'
---
name: research
description: Unified academic research lifecycle skill. Use for literature survey, paper reading, citation management, paper writing, and trend monitoring. Triggers on /research command.
---

# Research Skill — Placeholder
This file will be completed in Task 18 (Chunk 4).
EOF
```

- [ ] **Step 4: Commit**

```bash
git add skills/research/
git commit -m "feat: scaffold research skill directory structure"
```

### Task 2: Copy data files from citation-assistant

**Files:**
- Copy: `skills/research/data/ccf_2026.sqlite`
- Copy: `skills/research/data/ccf_2026.jsonl`
- Copy: `skills/research/data/impact_factor.sqlite3`

- [ ] **Step 1: Copy data files**

```bash
cp ~/.claude/skills/citation-assistant/data/ccf_2026.sqlite skills/research/data/
cp ~/.claude/skills/citation-assistant/data/ccf_2026.jsonl skills/research/data/
cp ~/.claude/skills/citation-assistant/data/impact_factor.sqlite3 skills/research/data/
```

- [ ] **Step 2: Verify files copied correctly**

```bash
sqlite3 skills/research/data/ccf_2026.sqlite "SELECT COUNT(*) FROM ccf_2026;"
sqlite3 skills/research/data/impact_factor.sqlite3 "SELECT COUNT(*) FROM factor;"
```

Expected: Both return non-zero counts.

- [ ] **Step 3: Commit**

```bash
git add skills/research/data/
git commit -m "feat: copy CCF and impact factor databases"
```

### Task 3: Create init.sh (adapted from citation-assistant)

**Files:**
- Create: `skills/research/scripts/init.sh`

- [ ] **Step 1: Write init.sh**

```bash
cat > skills/research/scripts/init.sh << 'INITEOF'
#!/bin/bash
# Initialize environment — load config and set path variables
# Usage: source scripts/init.sh

# Determine skill root directory
if [[ -n "${CLAUDE_SKILL_ROOT:-}" ]]; then
    SKILL_ROOT="${CLAUDE_SKILL_ROOT}"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SKILL_ROOT="$(dirname "$SCRIPT_DIR")"
fi

# Load .env if present
if [[ -f "$SKILL_ROOT/.env" ]]; then
    set -a
    source "$SKILL_ROOT/.env"
    set +a
fi

# Data directory
export SKILL_DATA_DIR="$SKILL_ROOT/data"

# Rate limit config
export S2_RATE_LIMIT_FILE="/tmp/.s2_rate_limit"
export S2_MIN_INTERVAL="${S2_MIN_INTERVAL:-1}"
export DBLP_RATE_LIMIT_FILE="/tmp/.dblp_rate_limit"
export DBLP_MIN_INTERVAL="${DBLP_MIN_INTERVAL:-1}"

# arXiv citation threshold
export ARXIV_CITATION_THRESHOLD="${ARXIV_CITATION_THRESHOLD:-100}"

# Helper: enforce rate limit for a given service
# Usage: rate_limit "$RATE_LIMIT_FILE" "$MIN_INTERVAL"
rate_limit() {
    local file="$1"
    local interval="$2"
    if [[ -f "$file" ]]; then
        local last_time
        last_time=$(cat "$file" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - last_time))
        if [[ $elapsed -lt $interval ]]; then
            sleep $((interval - elapsed))
        fi
    fi
    date +%s > "$file"
}
INITEOF
chmod +x skills/research/scripts/init.sh
```

- [ ] **Step 2: Verify init.sh sources without error**

```bash
bash -c 'source skills/research/scripts/init.sh && echo "SKILL_ROOT=$SKILL_ROOT"'
```

Expected: prints SKILL_ROOT path, no errors.

- [ ] **Step 3: Commit**

```bash
git add skills/research/scripts/init.sh
git commit -m "feat: add init.sh with rate limiting helpers"
```

### Task 4: Copy and adapt S2 search scripts

**Files:**
- Create: `skills/research/scripts/s2_search.sh` (adapted copy)
- Create: `skills/research/scripts/s2_bulk_search.sh` (adapted copy)

- [ ] **Step 1: Copy s2_search.sh with adaptations**

Copy from `~/.claude/skills/citation-assistant/scripts/s2_search.sh`. Adaptations:
- Use `source "$(dirname "$0")/init.sh"` instead of inline init
- Use `rate_limit` helper instead of inline rate limit code
- Change Chinese comments to English

```bash
cat > skills/research/scripts/s2_search.sh << 'EOF'
#!/bin/bash
# S2 relevance-ranked semantic search
# Usage: bash scripts/s2_search.sh "query" [limit]
# Returns: JSON objects (one per line), each with title, year, venue, citations, etc.

set -e

# Init
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-20}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

# Rate limit
rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

# URL encode
ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)

# Request
API_URL="https://api.semanticscholar.org/graph/v1/paper/search"
FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&limit=${LIMIT}&fields=${FIELDS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[]? |
            (.venue // .journal // "") as $venue |
            ($venue | test("(?i)arxiv")) as $is_arxiv |
            (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
             elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
             else "normal" end) as $arxiv_status |
            {
                paper_id: .paperId,
                title: .title,
                year: .year,
                venue: ($venue // "N/A"),
                citations: .citationCount,
                doi: .externalIds.DOI,
                arxiv_id: .externalIds.ArXiv,
                url: .url,
                abstract: (.abstract // ""),
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    429)
        echo '{"error": "S2 rate limit exceeded. Wait and retry, or use s2_bulk_search.sh"}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
EOF
chmod +x skills/research/scripts/s2_search.sh
```

- [ ] **Step 2: Copy s2_bulk_search.sh with same adaptations**

```bash
cat > skills/research/scripts/s2_bulk_search.sh << 'EOF'
#!/bin/bash
# S2 boolean bulk search — broader queries, sortable, up to 1000/call
# Usage: bash scripts/s2_bulk_search.sh "query" [year_range] [limit]
# Example: bash scripts/s2_bulk_search.sh "deep learning" "2020-" 50

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
YEAR_RANGE="${2:-}"
LIMIT="${3:-50}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_bulk_search.sh \"query\" [year_range] [limit]"}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://api.semanticscholar.org/graph/v1/paper/search/bulk"
FIELDS="title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"

PARAMS="query=${ENCODED_QUERY}&limit=${LIMIT}&fields=${FIELDS}"
if [[ -n "$YEAR_RANGE" ]]; then
    PARAMS="${PARAMS}&year=${YEAR_RANGE}"
fi

RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_URL}?${PARAMS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 60 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        TOTAL=$(echo "$BODY" | jq -r '.total // 0')
        RETURNED=$(echo "$BODY" | jq -r '.data | length')
        echo "{\"total\": $TOTAL, \"returned\": $RETURNED}" >&2

        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" --argjson req_limit "$LIMIT" '.data[:$req_limit][]? |
            (.venue // .journal // "") as $venue |
            ($venue | test("(?i)arxiv")) as $is_arxiv |
            (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
             elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
             else "normal" end) as $arxiv_status |
            {
                paper_id: .paperId,
                title: .title,
                year: .year,
                venue: ($venue // "N/A"),
                citations: .citationCount,
                doi: .externalIds.DOI,
                arxiv_id: .externalIds.ArXiv,
                url: .url,
                abstract: (.abstract // ""),
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    429)
        echo '{"error": "S2 rate limit exceeded. Wait 60 seconds."}' >&2
        exit 1
        ;;
    *)
        echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2
        exit 1
        ;;
esac
EOF
chmod +x skills/research/scripts/s2_bulk_search.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/research/scripts/s2_search.sh skills/research/scripts/s2_bulk_search.sh
git commit -m "feat: add S2 search and bulk search scripts"
```

### Task 4b: Write test for S2 search scripts

**Files:**
- Create: `skills/research/tests/test_s2_search.sh`

- [ ] **Step 1: Write test_s2_search.sh**

```bash
cat > skills/research/tests/test_s2_search.sh << 'TESTEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: s2_search returns results
echo "Test 1: s2_search for 'human pose estimation'..."
RESULT=$("$SCRIPTS/s2_search.sh" "human pose estimation" 5)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    ((PASS++))
else
    echo "  FAIL: No results"
    ((FAIL++))
fi

# Test 2: Results have required fields
echo "Test 2: Required fields present..."
HAS=$(echo "$RESULT" | head -1 | jq 'has("paper_id", "title", "citations", "source")')
if [[ "$HAS" == "true" ]]; then
    echo "  PASS"
    ((PASS++))
else
    echo "  FAIL"
    ((FAIL++))
fi

# Test 3: Source field is "s2"
echo "Test 3: Source is s2..."
SRC=$(echo "$RESULT" | head -1 | jq -r '.source')
if [[ "$SRC" == "s2" ]]; then
    echo "  PASS"
    ((PASS++))
else
    echo "  FAIL: source=$SRC"
    ((FAIL++))
fi

sleep 2

# Test 4: s2_bulk_search returns results with year filter
echo "Test 4: s2_bulk_search with year filter..."
RESULT=$("$SCRIPTS/s2_bulk_search.sh" "human pose estimation" "2023-" 5)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    ((PASS++))
else
    echo "  FAIL: No results"
    ((FAIL++))
fi

# Test 5: No arguments should fail
echo "Test 5: No arguments should error..."
if ! "$SCRIPTS/s2_search.sh" 2>/dev/null; then
    echo "  PASS"
    ((PASS++))
else
    echo "  FAIL"
    ((FAIL++))
fi

echo "---"
echo "s2_search: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_s2_search.sh
```

- [ ] **Step 2: Run test — should pass**

```bash
bash skills/research/tests/test_s2_search.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/research/tests/test_s2_search.sh
git commit -m "test: add S2 search script tests"
```

### Task 5: Copy quality evaluation scripts

**Files:**
- Create: `skills/research/scripts/author_info.sh`
- Create: `skills/research/scripts/venue_info.sh`
- Create: `skills/research/scripts/ccf_lookup.sh`
- Create: `skills/research/scripts/if_lookup.sh`

- [ ] **Step 1: Copy and adapt all four scripts**

Same pattern as Task 4: use `source init.sh`, use `rate_limit` helper, English comments. Copy from `~/.claude/skills/citation-assistant/scripts/`. Key adaptations:
- `author_info.sh`: replace inline rate limit with `rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"`
- `venue_info.sh`: replace inline `DATA_DIR` with `$SKILL_DATA_DIR` from init
- `ccf_lookup.sh`: same DATA_DIR fix
- `if_lookup.sh`: same DATA_DIR fix

The scripts' logic and SQL queries stay identical. Only the init pattern changes.

- [ ] **Step 2: Verify each script runs without error on known inputs**

```bash
bash skills/research/scripts/ccf_lookup.sh "CVPR" | jq .
bash skills/research/scripts/if_lookup.sh "Nature" | jq .
bash skills/research/scripts/venue_info.sh "CVPR" | jq .
```

Expected: JSON output with CCF/IF data.

- [ ] **Step 3: Commit**

```bash
git add skills/research/scripts/{author_info,venue_info,ccf_lookup,if_lookup}.sh
git commit -m "feat: add quality evaluation scripts (author, venue, CCF, IF)"
```

### Task 5b: Write test for quality evaluation scripts

**Files:**
- Create: `skills/research/tests/test_quality_eval.sh`

- [ ] **Step 1: Write test_quality_eval.sh**

```bash
cat > skills/research/tests/test_quality_eval.sh << 'TESTEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: CCF lookup for CVPR
echo "Test 1: CCF lookup for CVPR..."
RESULT=$("$SCRIPTS/ccf_lookup.sh" "CVPR")
if echo "$RESULT" | jq -e '.rank' > /dev/null 2>&1; then
    echo "  PASS: CCF rank found"
    ((PASS++))
else
    echo "  FAIL: No CCF rank"
    ((FAIL++))
fi

# Test 2: IF lookup for a known journal
echo "Test 2: IF lookup..."
RESULT=$("$SCRIPTS/if_lookup.sh" "Nature")
if echo "$RESULT" | jq -e '.factor' > /dev/null 2>&1; then
    echo "  PASS: IF found"
    ((PASS++))
else
    echo "  FAIL: No IF"
    ((FAIL++))
fi

# Test 3: Venue info returns summary
echo "Test 3: Venue info for CVPR..."
RESULT=$("$SCRIPTS/venue_info.sh" "CVPR")
if echo "$RESULT" | jq -e '.summary' > /dev/null 2>&1; then
    echo "  PASS: Summary present"
    ((PASS++))
else
    echo "  FAIL: No summary"
    ((FAIL++))
fi

echo "---"
echo "quality_eval: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_quality_eval.sh
```

- [ ] **Step 2: Run test — should pass**

```bash
bash skills/research/tests/test_quality_eval.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/research/tests/test_quality_eval.sh
git commit -m "test: add quality evaluation script tests"
```

### Task 6: Copy CrossRef and BibTeX scripts

**Files:**
- Create: `skills/research/scripts/crossref_search.sh`
- Create: `skills/research/scripts/doi2bibtex.sh`

- [ ] **Step 1: Copy both scripts**

Copy from citation-assistant. Minimal changes — these don't use S2 rate limiting. Change Chinese comments to English.

- [ ] **Step 2: Verify crossref_search.sh**

```bash
bash skills/research/scripts/crossref_search.sh "deep residual learning" 3 | jq .
```

Expected: JSON with title, year, venue, citations, doi.

- [ ] **Step 3: Verify doi2bibtex.sh**

```bash
bash skills/research/scripts/doi2bibtex.sh "10.1109/CVPR.2016.90"
```

Expected: BibTeX entry for ResNet paper.

- [ ] **Step 4: Commit**

```bash
git add skills/research/scripts/{crossref_search,doi2bibtex}.sh
git commit -m "feat: add CrossRef search and DOI-to-BibTeX scripts"
```

### Task 6b: Write test for CrossRef scripts

**Files:**
- Create: `skills/research/tests/test_crossref.sh`

- [ ] **Step 1: Write test_crossref.sh**

```bash
cat > skills/research/tests/test_crossref.sh << 'TESTEOF'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: CrossRef search returns results
echo "Test 1: CrossRef search..."
RESULT=$("$SCRIPTS/crossref_search.sh" "deep residual learning" 3)
COUNT=$(echo "$RESULT" | jq -s 'length')
if [[ "$COUNT" -gt 0 ]]; then
    echo "  PASS: Got $COUNT results"
    ((PASS++))
else
    echo "  FAIL: No results"
    ((FAIL++))
fi

# Test 2: Results have DOI
echo "Test 2: Results have DOI..."
DOI=$(echo "$RESULT" | head -1 | jq -r '.doi // empty')
if [[ -n "$DOI" ]]; then
    echo "  PASS: doi=$DOI"
    ((PASS++))
else
    echo "  FAIL: No DOI"
    ((FAIL++))
fi

# Test 3: doi2bibtex returns valid BibTeX
echo "Test 3: doi2bibtex..."
BIB=$("$SCRIPTS/doi2bibtex.sh" "10.1109/CVPR.2016.90")
if echo "$BIB" | grep -q "@"; then
    echo "  PASS: Valid BibTeX"
    ((PASS++))
else
    echo "  FAIL: Invalid BibTeX"
    ((FAIL++))
fi

# Test 4: doi2bibtex with no args should fail
echo "Test 4: No args should error..."
if ! "$SCRIPTS/doi2bibtex.sh" 2>/dev/null; then
    echo "  PASS"
    ((PASS++))
else
    echo "  FAIL"
    ((FAIL++))
fi

echo "---"
echo "crossref: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_crossref.sh
```

- [ ] **Step 2: Run test — should pass**

```bash
bash skills/research/tests/test_crossref.sh
```

- [ ] **Step 3: Commit**

```bash
git add skills/research/tests/test_crossref.sh
git commit -m "test: add CrossRef script tests"
```

---

## Chunk 2: New Scripts — S2 Network, DBLP, HF, S2 Batch

### Task 7: Create s2_batch.sh

**Files:**
- Create: `skills/research/scripts/s2_batch.sh`

- [ ] **Step 1: Write the test**

```bash
cat > skills/research/tests/test_s2_batch.sh << 'TESTEOF'
#!/bin/bash
# Test s2_batch.sh — batch metadata fetch by paper IDs
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
    ((PASS++))
else
    echo "  FAIL: Expected 2, got $COUNT"
    ((FAIL++))
fi

# Test 2: Each result has required fields
echo "Test 2: Results have required fields..."
HAS_FIELDS=$(echo "$RESULT" | head -1 | jq 'has("paper_id", "title", "citations", "venue")')
if [[ "$HAS_FIELDS" == "true" ]]; then
    echo "  PASS: Required fields present"
    ((PASS++))
else
    echo "  FAIL: Missing required fields"
    ((FAIL++))
fi

# Test 3: No arguments should fail
echo "Test 3: No arguments should error..."
if ! "$SCRIPTS/s2_batch.sh" 2>/dev/null; then
    echo "  PASS: Correctly errored on no input"
    ((PASS++))
else
    echo "  FAIL: Should have errored"
    ((FAIL++))
fi

echo "---"
echo "s2_batch: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_s2_batch.sh
```

- [ ] **Step 2: Run test — should fail (script doesn't exist yet)**

```bash
bash skills/research/tests/test_s2_batch.sh
```

Expected: FAIL — script not found.

- [ ] **Step 3: Write s2_batch.sh**

```bash
cat > skills/research/scripts/s2_batch.sh << 'EOF'
#!/bin/bash
# S2 batch paper metadata — NOT a search. Takes known paper IDs, returns details.
# Usage: bash scripts/s2_batch.sh "id1" "id2" ... (up to 500)
# Also accepts IDs via stdin (one per line)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

# Collect IDs from arguments or stdin
IDS=()
if [[ $# -gt 0 ]]; then
    IDS=("$@")
elif [[ ! -t 0 ]]; then
    while IFS= read -r line; do
        [[ -n "$line" ]] && IDS+=("$line")
    done
fi

if [[ ${#IDS[@]} -eq 0 ]]; then
    echo '{"error": "Usage: bash scripts/s2_batch.sh id1 id2 ... (or pipe IDs via stdin)"}' >&2
    exit 1
fi

FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/batch"

# Chunk into groups of 500
CHUNK_SIZE=500
for ((i=0; i<${#IDS[@]}; i+=CHUNK_SIZE)); do
    CHUNK=("${IDS[@]:i:CHUNK_SIZE}")

    # Build JSON body
    JSON_BODY=$(printf '%s\n' "${CHUNK[@]}" | jq -R . | jq -s '{ ids: . }')

    rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "$API_URL?fields=$FIELDS" \
        -H "Content-Type: application/json" \
        ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
        -d "$JSON_BODY" \
        --max-time 60 2>/dev/null)

    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')

    case "$HTTP_CODE" in
        200)
            echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.[]? | select(. != null) |
                (.venue // .journal // "") as $venue |
                ($venue | test("(?i)arxiv")) as $is_arxiv |
                (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
                 elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
                 else "normal" end) as $arxiv_status |
                {
                    paper_id: .paperId,
                    title: .title,
                    year: .year,
                    venue: ($venue // "N/A"),
                    citations: .citationCount,
                    doi: .externalIds.DOI,
                    arxiv_id: .externalIds.ArXiv,
                    url: .url,
                    open_access_pdf: (.openAccessPdf.url // null),
                    is_arxiv: $is_arxiv,
                    arxiv_status: $arxiv_status,
                    authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                    source: "s2"
                }'
            ;;
        429)
            echo '{"error": "S2 rate limit exceeded."}' >&2
            exit 1
            ;;
        *)
            echo "{\"error\": \"S2 batch HTTP $HTTP_CODE\"}" >&2
            exit 1
            ;;
    esac
done
EOF
chmod +x skills/research/scripts/s2_batch.sh
```

- [ ] **Step 4: Run test — should pass**

```bash
bash skills/research/tests/test_s2_batch.sh
```

Expected: 3 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add skills/research/scripts/s2_batch.sh skills/research/tests/test_s2_batch.sh
git commit -m "feat: add s2_batch.sh with tests"
```

### Task 8: Create s2_citations.sh and s2_references.sh

**Files:**
- Create: `skills/research/scripts/s2_citations.sh`
- Create: `skills/research/scripts/s2_references.sh`

- [ ] **Step 1: Write the test**

```bash
cat > skills/research/tests/test_s2_network.sh << 'TESTEOF'
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
    ((PASS++))
else
    echo "  FAIL: No citations returned"
    ((FAIL++))
fi

sleep 1

# Test 2: References returns results
echo "Test 2: s2_references returns results..."
REF_RESULT=$("$SCRIPTS/s2_references.sh" "$RESNET_ID" 5)
REF_COUNT=$(echo "$REF_RESULT" | jq -s 'length')
if [[ "$REF_COUNT" -gt 0 ]]; then
    echo "  PASS: Got $REF_COUNT referenced papers"
    ((PASS++))
else
    echo "  FAIL: No references returned"
    ((FAIL++))
fi

# Test 3: Citations have required fields
echo "Test 3: Citation results have required fields..."
HAS_FIELDS=$(echo "$CIT_RESULT" | head -1 | jq 'has("paper_id", "title", "citations")')
if [[ "$HAS_FIELDS" == "true" ]]; then
    echo "  PASS"
    ((PASS++))
else
    echo "  FAIL"
    ((FAIL++))
fi

echo "---"
echo "s2_network: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_s2_network.sh
```

- [ ] **Step 2: Run test — should fail**

```bash
bash skills/research/tests/test_s2_network.sh
```

- [ ] **Step 3: Write s2_citations.sh**

```bash
cat > skills/research/scripts/s2_citations.sh << 'EOF'
#!/bin/bash
# S2 citation traversal — find papers that cited a given paper
# Usage: bash scripts/s2_citations.sh "paper_id" [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

PAPER_ID="${1:-}"
LIMIT="${2:-100}"

if [[ -z "$PAPER_ID" ]]; then
    echo '{"error": "Usage: bash scripts/s2_citations.sh \"paper_id\" [limit]"}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/${PAPER_ID}/citations"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_URL}?fields=${FIELDS}&limit=${LIMIT}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[]?.citingPaper |
            select(.paperId != null) |
            (.venue // .journal // "") as $venue |
            ($venue | test("(?i)arxiv")) as $is_arxiv |
            (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
             elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
             else "normal" end) as $arxiv_status |
            {
                paper_id: .paperId,
                title: .title,
                year: .year,
                venue: ($venue // "N/A"),
                citations: .citationCount,
                doi: .externalIds.DOI,
                arxiv_id: .externalIds.ArXiv,
                url: .url,
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
EOF
chmod +x skills/research/scripts/s2_citations.sh
```

- [ ] **Step 4: Write s2_references.sh**

Same pattern as s2_citations.sh but uses `/paper/{id}/references` and `.citedPaper` instead of `.citingPaper`.

```bash
cat > skills/research/scripts/s2_references.sh << 'EOF'
#!/bin/bash
# S2 reference traversal — find papers cited by a given paper
# Usage: bash scripts/s2_references.sh "paper_id" [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

PAPER_ID="${1:-}"
LIMIT="${2:-100}"

if [[ -z "$PAPER_ID" ]]; then
    echo '{"error": "Usage: bash scripts/s2_references.sh \"paper_id\" [limit]"}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/${PAPER_ID}/references"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_URL}?fields=${FIELDS}&limit=${LIMIT}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[]?.citedPaper |
            select(.paperId != null) |
            (.venue // .journal // "") as $venue |
            ($venue | test("(?i)arxiv")) as $is_arxiv |
            (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
             elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
             else "normal" end) as $arxiv_status |
            {
                paper_id: .paperId,
                title: .title,
                year: .year,
                venue: ($venue // "N/A"),
                citations: .citationCount,
                doi: .externalIds.DOI,
                arxiv_id: .externalIds.ArXiv,
                url: .url,
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
EOF
chmod +x skills/research/scripts/s2_references.sh
```

- [ ] **Step 5: Run test — should pass**

```bash
bash skills/research/tests/test_s2_network.sh
```

Expected: 3 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add skills/research/scripts/{s2_citations,s2_references}.sh skills/research/tests/test_s2_network.sh
git commit -m "feat: add S2 citation and reference traversal scripts"
```

### Task 9: Create s2_recommend.sh, s2_snippet.sh, s2_match.sh

**Files:**
- Create: `skills/research/scripts/s2_recommend.sh`
- Create: `skills/research/scripts/s2_snippet.sh`
- Create: `skills/research/scripts/s2_match.sh`

- [ ] **Step 1: Write s2_recommend.sh**

```bash
cat > skills/research/scripts/s2_recommend.sh << 'EOF'
#!/bin/bash
# S2 paper recommendations — given positive/negative example papers
# Usage: bash scripts/s2_recommend.sh "pos_id1,pos_id2" ["neg_id1,neg_id2"] [limit]
# pos_ids: comma-separated paper IDs to use as positive examples
# neg_ids: comma-separated paper IDs to use as negative examples (optional)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

POS_IDS="${1:-}"
NEG_IDS="${2:-}"
LIMIT="${3:-100}"

if [[ -z "$POS_IDS" ]]; then
    echo '{"error": "Usage: bash scripts/s2_recommend.sh \"pos_id1,pos_id2\" [\"neg_id1\"] [limit]"}' >&2
    exit 1
fi

# Build JSON arrays
POS_JSON=$(echo "$POS_IDS" | tr ',' '\n' | jq -R . | jq -s .)
NEG_JSON="[]"
if [[ -n "$NEG_IDS" ]]; then
    NEG_JSON=$(echo "$NEG_IDS" | tr ',' '\n' | jq -R . | jq -s .)
fi

JSON_BODY=$(jq -n --argjson pos "$POS_JSON" --argjson neg "$NEG_JSON" \
    '{ positivePaperIds: $pos, negativePaperIds: $neg }')

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract"
API_URL="https://api.semanticscholar.org/recommendations/v1/papers/"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST "${API_URL}?fields=${FIELDS}&limit=${LIMIT}" \
    -H "Content-Type: application/json" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    -d "$JSON_BODY" \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq '.recommendedPapers[]? | {
            paper_id: .paperId,
            title: .title,
            year: .year,
            venue: (.venue // .journal // "N/A"),
            citations: .citationCount,
            doi: .externalIds.DOI,
            arxiv_id: .externalIds.ArXiv,
            url: .url,
            authors: [.authors[]? | { name: .name, id: .authorId }][:3],
            source: "s2_recommend"
        }'
        ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 recommend HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
EOF
chmod +x skills/research/scripts/s2_recommend.sh
```

- [ ] **Step 2: Write s2_snippet.sh**

```bash
cat > skills/research/scripts/s2_snippet.sh << 'EOF'
#!/bin/bash
# S2 snippet search — find ~500-word passages matching a query in paper bodies
# Usage: bash scripts/s2_snippet.sh "query" [limit]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-10}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_snippet.sh \"query\" [limit]"}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://api.semanticscholar.org/graph/v1/snippet/search"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&limit=${LIMIT}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq '.data[]? | {
            paper_id: .paperId,
            title: .title,
            snippet: .snippet.text,
            snippet_section: .snippet.section,
            url: .url,
            source: "s2_snippet"
        }'
        ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 snippet HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
EOF
chmod +x skills/research/scripts/s2_snippet.sh
```

- [ ] **Step 3: Write s2_match.sh**

```bash
cat > skills/research/scripts/s2_match.sh << 'EOF'
#!/bin/bash
# S2 exact title match — returns single closest match
# Usage: bash scripts/s2_match.sh "paper title"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/s2_match.sh \"paper title\""}' >&2
    exit 1
fi

rate_limit "$S2_RATE_LIMIT_FILE" "$S2_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
FIELDS="paperId,title,year,authors,venue,journal,citationCount,externalIds,url,abstract,openAccessPdf"
API_URL="https://api.semanticscholar.org/graph/v1/paper/search/match"

RESPONSE=$(curl -s -w "\n%{http_code}" \
    "${API_URL}?query=${ENCODED_QUERY}&fields=${FIELDS}" \
    ${S2_API_KEY:+-H "x-api-key: $S2_API_KEY"} \
    --max-time 30 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
    200)
        echo "$BODY" | jq --arg threshold "$ARXIV_CITATION_THRESHOLD" '.data[0]? |
            select(. != null) |
            (.venue // .journal // "") as $venue |
            ($venue | test("(?i)arxiv")) as $is_arxiv |
            (if $is_arxiv and .citationCount < ($threshold | tonumber) then "caution"
             elif $is_arxiv and .citationCount >= ($threshold | tonumber) then "recommended"
             else "normal" end) as $arxiv_status |
            {
                paper_id: .paperId,
                title: .title,
                year: .year,
                venue: ($venue // "N/A"),
                citations: .citationCount,
                doi: .externalIds.DOI,
                arxiv_id: .externalIds.ArXiv,
                url: .url,
                open_access_pdf: (.openAccessPdf.url // null),
                is_arxiv: $is_arxiv,
                arxiv_status: $arxiv_status,
                authors: [.authors[]? | { name: .name, id: .authorId }][:3],
                source: "s2"
            }'
        ;;
    404) echo '{"error": "No matching paper found"}' >&2; exit 1 ;;
    429) echo '{"error": "S2 rate limit exceeded."}' >&2; exit 1 ;;
    *)   echo "{\"error\": \"S2 match HTTP $HTTP_CODE\"}" >&2; exit 1 ;;
esac
EOF
chmod +x skills/research/scripts/s2_match.sh
```

- [ ] **Step 4: Commit**

```bash
git add skills/research/scripts/{s2_recommend,s2_snippet,s2_match}.sh
git commit -m "feat: add S2 recommend, snippet search, and title match scripts"
```

### Task 10: Create DBLP scripts

**Files:**
- Create: `skills/research/scripts/dblp_search.sh`
- Create: `skills/research/scripts/dblp_bibtex.sh`
- Create: `skills/research/tests/test_dblp.sh`

- [ ] **Step 1: Write the test**

```bash
cat > skills/research/tests/test_dblp.sh << 'TESTEOF'
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
    ((PASS++))
else
    echo "  FAIL: No results"
    ((FAIL++))
fi

# Test 2: Result has dblp_key
echo "Test 2: Result has dblp_key..."
KEY=$(echo "$RESULT" | head -1 | jq -r '.dblp_key // empty')
if [[ -n "$KEY" ]]; then
    echo "  PASS: dblp_key=$KEY"
    ((PASS++))
else
    echo "  FAIL: No dblp_key"
    ((FAIL++))
fi

sleep 1

# Test 3: Fetch BibTeX for known key
echo "Test 3: Fetch BibTeX for conf/cvpr/HeZRS16..."
BIB=$("$SCRIPTS/dblp_bibtex.sh" "conf/cvpr/HeZRS16")
if echo "$BIB" | grep -q "@inproceedings"; then
    echo "  PASS: Got valid BibTeX"
    ((PASS++))
else
    echo "  FAIL: Invalid BibTeX"
    ((FAIL++))
fi

echo "---"
echo "dblp: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_dblp.sh
```

- [ ] **Step 2: Run test — should fail**

```bash
bash skills/research/tests/test_dblp.sh
```

- [ ] **Step 3: Write dblp_search.sh**

```bash
cat > skills/research/scripts/dblp_search.sh << 'EOF'
#!/bin/bash
# DBLP publication search
# Usage: bash scripts/dblp_search.sh "query" [limit]
# Returns: JSON objects with title, year, venue, dblp_key, authors

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

QUERY="${1:-}"
LIMIT="${2:-10}"

if [[ -z "$QUERY" ]]; then
    echo '{"error": "Usage: bash scripts/dblp_search.sh \"query\" [limit]"}' >&2
    exit 1
fi

rate_limit "$DBLP_RATE_LIMIT_FILE" "$DBLP_MIN_INTERVAL"

ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
API_URL="https://dblp.org/search/publ/api"

RESPONSE=$(curl -s \
    "${API_URL}?q=${ENCODED_QUERY}&format=json&h=${LIMIT}" \
    --max-time 30 2>/dev/null)

if [[ -z "$RESPONSE" ]]; then
    echo '{"error": "DBLP request failed"}' >&2
    exit 1
fi

echo "$RESPONSE" | jq '.result.hits.hit[]? | {
    dblp_key: .info.key,
    title: .info.title,
    year: (.info.year | tonumber? // null),
    venue: .info.venue,
    authors: (if .info.authors.author | type == "array" then
        [.info.authors.author[]? | .text][:3]
    else
        [.info.authors.author.text // "N/A"]
    end),
    doi: .info.doi,
    url: .info.url,
    source: "dblp"
}'
EOF
chmod +x skills/research/scripts/dblp_search.sh
```

- [ ] **Step 4: Write dblp_bibtex.sh**

```bash
cat > skills/research/scripts/dblp_bibtex.sh << 'EOF'
#!/bin/bash
# DBLP BibTeX fetch — given a DBLP key, return the .bib entry
# Usage: bash scripts/dblp_bibtex.sh "conf/cvpr/HeZRS16"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/init.sh"

DBLP_KEY="${1:-}"

if [[ -z "$DBLP_KEY" ]]; then
    echo '{"error": "Usage: bash scripts/dblp_bibtex.sh \"dblp_key\""}' >&2
    exit 1
fi

rate_limit "$DBLP_RATE_LIMIT_FILE" "$DBLP_MIN_INTERVAL"

RESPONSE=$(curl -s \
    "https://dblp.org/rec/${DBLP_KEY}.bib" \
    --max-time 30 2>/dev/null)

if [[ -z "$RESPONSE" ]] || echo "$RESPONSE" | grep -q "404"; then
    echo "{\"error\": \"DBLP BibTeX not found for key: $DBLP_KEY\"}" >&2
    exit 1
fi

echo "$RESPONSE"
EOF
chmod +x skills/research/scripts/dblp_bibtex.sh
```

- [ ] **Step 5: Run test — should pass**

```bash
bash skills/research/tests/test_dblp.sh
```

Expected: 3 passed, 0 failed.

- [ ] **Step 6: Commit**

```bash
git add skills/research/scripts/{dblp_search,dblp_bibtex}.sh skills/research/tests/test_dblp.sh
git commit -m "feat: add DBLP search and BibTeX scripts with tests"
```

### Task 11: Create hf_daily_papers.sh

**Files:**
- Create: `skills/research/scripts/hf_daily_papers.sh`
- Create: `skills/research/tests/test_hf_daily.sh`

- [ ] **Step 1: Write the test**

```bash
cat > skills/research/tests/test_hf_daily.sh << 'TESTEOF'
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
    ((PASS++))
else
    echo "  FAIL: No papers"
    ((FAIL++))
fi

echo "Test 2: Papers have required fields..."
HAS=$(echo "$RESULT" | head -1 | jq 'has("title", "arxiv_id", "upvotes")')
if [[ "$HAS" == "true" ]]; then
    echo "  PASS"
    ((PASS++))
else
    echo "  FAIL"
    ((FAIL++))
fi

echo "---"
echo "hf_daily: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_hf_daily.sh
```

- [ ] **Step 2: Write hf_daily_papers.sh**

```bash
cat > skills/research/scripts/hf_daily_papers.sh << 'EOF'
#!/bin/bash
# Fetch HF daily (trending) papers
# Usage: bash scripts/hf_daily_papers.sh [limit]

set -e

LIMIT="${1:-20}"

RESPONSE=$(curl -s \
    "https://huggingface.co/api/daily_papers" \
    --max-time 30 2>/dev/null)

if [[ -z "$RESPONSE" ]]; then
    echo '{"error": "HF daily papers request failed"}' >&2
    exit 1
fi

echo "$RESPONSE" | jq --argjson limit "$LIMIT" '.[:$limit][] | {
    title: .paper.title,
    arxiv_id: .paper.id,
    summary: (.paper.summary // "")[:300],
    ai_summary: (.ai_summary // ""),
    ai_keywords: (.ai_keywords // []),
    authors: [.paper.authors[]?.name][:3],
    upvotes: (.paper.upvotes // 0),
    comments: (.numComments // 0),
    published_at: .paper.publishedAt,
    github_repo: (.githubRepo // null),
    github_stars: (.githubStars // null),
    source: "hf_daily"
}'
EOF
chmod +x skills/research/scripts/hf_daily_papers.sh
```

- [ ] **Step 3: Run test — should pass**

```bash
bash skills/research/tests/test_hf_daily.sh
```

- [ ] **Step 4: Commit**

```bash
git add skills/research/scripts/hf_daily_papers.sh skills/research/tests/test_hf_daily.sh
git commit -m "feat: add HF daily papers script with tests"
```

### Task 12: Create integration test — cite chain

**Files:**
- Create: `skills/research/tests/test_cite_chain.sh`

- [ ] **Step 1: Write cite chain integration test**

```bash
cat > skills/research/tests/test_cite_chain.sh << 'TESTEOF'
#!/bin/bash
# Integration test: full DBLP > CrossRef > S2 citation chain
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$SCRIPT_DIR/../scripts"
PASS=0; FAIL=0

# Test 1: DBLP should find ResNet
echo "Test 1: Cite chain — DBLP finds ResNet..."
DBLP_RESULT=$("$SCRIPTS/dblp_search.sh" "Deep Residual Learning for Image Recognition" 1)
DBLP_KEY=$(echo "$DBLP_RESULT" | jq -r '.dblp_key // empty')
if [[ -n "$DBLP_KEY" ]]; then
    echo "  PASS: Found DBLP key=$DBLP_KEY"
    ((PASS++))

    sleep 1

    # Fetch BibTeX
    BIB=$("$SCRIPTS/dblp_bibtex.sh" "$DBLP_KEY")
    if echo "$BIB" | grep -q "@"; then
        echo "  PASS: Got BibTeX via DBLP"
        ((PASS++))
    else
        echo "  FAIL: BibTeX fetch failed"
        ((FAIL++))
    fi
else
    echo "  FAIL: DBLP did not find paper"
    ((FAIL++))
    ((FAIL++))
fi

sleep 1

# Test 2: CrossRef as fallback (use DOI directly)
echo "Test 2: Cite chain — CrossRef DOI fallback..."
BIB_CR=$("$SCRIPTS/doi2bibtex.sh" "10.1109/CVPR.2016.90")
if echo "$BIB_CR" | grep -q "He"; then
    echo "  PASS: Got BibTeX via CrossRef DOI"
    ((PASS++))
else
    echo "  FAIL: CrossRef DOI fallback failed"
    ((FAIL++))
fi

sleep 1

# Test 3: S2 match as last resort
echo "Test 3: Cite chain — S2 title match fallback..."
S2_RESULT=$("$SCRIPTS/s2_match.sh" "Deep Residual Learning for Image Recognition")
S2_TITLE=$(echo "$S2_RESULT" | jq -r '.title // empty')
if [[ -n "$S2_TITLE" ]]; then
    echo "  PASS: S2 matched title=$S2_TITLE"
    ((PASS++))
else
    echo "  FAIL: S2 match failed"
    ((FAIL++))
fi

echo "---"
echo "cite_chain: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
TESTEOF
chmod +x skills/research/tests/test_cite_chain.sh
```

- [ ] **Step 2: Run test**

```bash
bash skills/research/tests/test_cite_chain.sh
```

Expected: 4 passed, 0 failed.

- [ ] **Step 3: Commit**

```bash
git add skills/research/tests/test_cite_chain.sh
git commit -m "test: add cite chain integration test"
```

### Task 13: Create test runner

**Files:**
- Create: `skills/research/tests/run_all_tests.sh`

- [ ] **Step 1: Write test runner**

```bash
cat > skills/research/tests/run_all_tests.sh << 'EOF'
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
        ((TOTAL_FAIL++))
    fi
    ((TESTS_RUN++))

    # Rate limit between test files
    sleep 2
done

echo ""
echo "========================================="
echo "Test suites run: $TESTS_RUN"
echo "Suites with failures: $TOTAL_FAIL"
echo "========================================="

[[ $TOTAL_FAIL -eq 0 ]]
EOF
chmod +x skills/research/tests/run_all_tests.sh
```

- [ ] **Step 2: Run all tests**

```bash
bash skills/research/tests/run_all_tests.sh
```

Expected: All test suites pass.

- [ ] **Step 3: Commit**

```bash
git add skills/research/tests/run_all_tests.sh
git commit -m "test: add test runner for all test suites"
```

---

## Chunk 3: Phase Modules

### Task 14: Write discover.md

**Files:**
- Create: `skills/research/phases/discover.md`

- [ ] **Step 1: Write discover.md**

The discover phase prompt instructs the model to:
1. Parse the user's research query
2. Dispatch three parallel search agents (S2, AlphaXiv MCP, HF MCP)
3. Run a merge agent to deduplicate by arXiv ID / DOI / title similarity
4. Run quality evaluation using scripts (s2_batch, venue_info, author_info, ccf_lookup, if_lookup)
5. Compute composite scores and rank
6. Save results to `.research-workspace/sessions/{slug}/discover.json`
7. Present ranked results with quality report

Include the full scoring formula, arXiv classification rules, and expansion options (s2_citations, s2_references, s2_recommend).

- [ ] **Step 2: Commit**

```bash
git add skills/research/phases/discover.md
git commit -m "feat: add discover phase module"
```

### Task 15: Write triage.md and read.md

**Files:**
- Create: `skills/research/phases/triage.md`
- Create: `skills/research/phases/read.md`

- [ ] **Step 1: Write triage.md**

Instructions for quick screening:
- For each paper from discover results, fetch AlphaXiv MCP `get_paper_content` (report mode)
- Fallback: curl `alphaxiv.org/overview/{ID}.md`
- Conference-only fallback: S2 `openAccessPdf` or publisher page
- Generate 1-2 sentence relevance verdict
- Save to `triage.json`

- [ ] **Step 2: Write read.md**

Instructions for deep analysis:
- Content access fallback chain (4 levels + conference-only)
- Appendix/supplementary material access via conference page
- AlphaXiv MCP `read_files_from_github_repository` for code
- s2_snippet.sh for cross-paper evidence
- Structured output template (research question, methodology, findings, limitations, relevance)
- Save to `read/{paper_id}.json`

- [ ] **Step 3: Commit**

```bash
git add skills/research/phases/{triage,read}.md
git commit -m "feat: add triage and read phase modules"
```

### Task 16: Write cite.md and write.md

**Files:**
- Create: `skills/research/phases/cite.md`
- Create: `skills/research/phases/write.md`

- [ ] **Step 1: Write cite.md**

Instructions for verified BibTeX generation:
- DBLP > CrossRef > S2 chain with exact steps
- DBLP matching strategy (>90% token overlap, word-level, case-insensitive)
- S2-constructed BibTeX caveat
- Iron rules (never from memory, always from API)
- Quality evaluation per entry
- Source tagging ("via DBLP", etc.)
- Save to `cite/{paper_id}.bib` and `cite/cite-log.json`

- [ ] **Step 2: Write write.md**

Instructions for paper writing:
- Output format auto-detection (`.tex` files present → LaTeX; else ask user)
- Context sources (`.tex` files, Notion, workspace)
- Invoke `ml-paper-writing` skill for structure
- Invoke `humanizer` skill for style
- Every `\cite{}` verified through cite phase
- User confirmation before output

- [ ] **Step 3: Commit**

```bash
git add skills/research/phases/{cite,write}.md
git commit -m "feat: add cite and write phase modules"
```

### Task 17: Write trending.md

**Files:**
- Create: `skills/research/phases/trending.md`

- [ ] **Step 1: Write trending.md**

Instructions for trending paper digest:
- Sources: HF daily papers (hf_daily_papers.sh), AlphaXiv MCP (embedding_similarity_search with broad query, fallback curl)
- Personalization filter with tier definitions (high/medium/low)
- Research profile reference
- Output format: curated digest with relevance tags

- [ ] **Step 2: Commit**

```bash
git add skills/research/phases/trending.md
git commit -m "feat: add trending phase module"
```

---

## Chunk 4: Orchestrator and Final Integration

### Task 18: Write SKILL.md orchestrator

**Files:**
- Modify: `skills/research/SKILL.md`

- [ ] **Step 1: Write the full SKILL.md**

The orchestrator must:
1. Define skill metadata (name, description, triggers)
2. Preload `high-agency` skill on every invocation
3. Check AlphaXiv MCP connectivity
4. Parse user intent from `/research <args>`
5. Route to appropriate phase(s)
6. Create `.research-workspace/` on first run
7. Include setup requirements and installation prompt
8. Include degraded mode rules
9. Include iron rules
10. Include language rules (English, GRE-level Chinese gloss)

- [ ] **Step 2: Commit**

```bash
git add skills/research/SKILL.md
git commit -m "feat: complete research skill orchestrator"
```

### Task 19: End-to-end smoke test

- [ ] **Step 1: Run all unit tests**

```bash
bash skills/research/tests/run_all_tests.sh
```

Expected: All pass.

- [ ] **Step 2: Manual smoke test — cite a known paper**

Invoke `/research cite 1512.03385` (ResNet) and verify:
- DBLP finds it
- BibTeX is fetched
- Source tag is "via DBLP"

- [ ] **Step 3: Manual smoke test — search**

Invoke `/research survey "multimodal emotion recognition"` and verify:
- Three search agents return results
- Merge deduplicates
- Quality scores computed
- Results ranked and saved to workspace

- [ ] **Step 4: Commit final state**

```bash
git add -A skills/research/
git commit -m "feat: research skill complete — all tests passing"
```

---

## Chunk 5: Discovery Test — "MME-Emotion" on ICLR 2026

### Task 20: Run discovery for "MME-Emotion"

- [ ] **Step 1: Execute discovery**

```
/research survey "MME-Emotion multimodal emotion recognition benchmark ICLR 2026"
```

- [ ] **Step 2: Review results and triage**

Select top papers for deep reading based on quality scores.

- [ ] **Step 3: Deep read selected papers**

Use `/research read {paper_id}` for top candidates.

- [ ] **Step 4: Discuss breakthroughs with 170-video dataset**

Based on the survey findings, discuss:
- What gaps exist in current multimodal emotion recognition
- How 170 videos could be leveraged
- Potential research directions aligned with user's expertise (low-visibility, VLM, MLLM)
