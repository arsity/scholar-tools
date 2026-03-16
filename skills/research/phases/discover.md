# Discover Phase

Search, merge, evaluate, and rank papers for a research topic.

## Trigger

Called when user invokes `/research survey "topic"` or `/research discover "topic"`.

## Workflow

### Step 1: Parse query

Extract the user's research query. If ambiguous, ask one clarifying question before proceeding.

### Step 2: Parallel search — dispatch three agents

Launch three search agents in parallel. Each has a 60-second timeout. If an agent errors or times out, proceed with results from the others.

**Agent 1: Semantic Scholar**

Run sequentially (1 req/sec rate limit):

```bash
bash scripts/s2_search.sh "<query>" 20
```

If the user specifies a year range or boolean operators, also run:

```bash
bash scripts/s2_bulk_search.sh "<query>" "<year_range>" 50
```

Each result includes `paper_id`, `title`, `year`, `venue`, `citations`, `doi`, `arxiv_id`, `source: "s2"`.

**Agent 2: AlphaXiv MCP**

Use AlphaXiv MCP tools (if available):
- `embedding_similarity_search` with the query for semantic search
- `full_text_papers_search` with key terms for keyword search

If AlphaXiv MCP is unavailable, skip this agent (degraded mode).

**Agent 3: Hugging Face MCP**

Use HF MCP tool:
- `mcp__claude_ai_Hugging_Face__paper_search` with the query (returns up to 12 results)

### Step 3: Merge

Receive results from all agents. Deduplicate:
1. By arXiv ID (exact match)
2. By DOI (exact match)
3. By title similarity (>85% word-level overlap, case-insensitive)

Normalize all results to a common format:
```json
{
  "paper_id": "s2_id or arxiv_id",
  "title": "...",
  "year": 2024,
  "venue": "...",
  "citations": 123,
  "doi": "...",
  "arxiv_id": "...",
  "authors": [{"name": "...", "id": "..."}],
  "source": "s2|alphaxiv|hf",
  "found_in": ["s2", "alphaxiv"]
}
```

### Step 4: Quality evaluation

For each paper in the merged list:

1. **Batch metadata**: Run `s2_batch.sh` with all paper IDs to fill missing metadata (citation counts, venues, author IDs). Chunk into groups of 500 max.

2. **Venue quality**: For each unique venue, run:
   ```bash
   bash scripts/venue_info.sh "<venue>"
   ```
   This returns CCF rank, JCR quartile, CAS quartile, impact factor.

3. **Author quality**: For first author of each paper (where author ID is available):
   ```bash
   bash scripts/author_info.sh "<author_id>"
   ```

4. **arXiv classification**:
   - `recommended`: arXiv paper with citations >= 100
   - `caution`: arXiv paper with citations < 100
   - `normal`: formally published (not arXiv)

5. **Composite score**:

   | Dimension       | Weight | Calculation                       |
   | --------------- | ------ | --------------------------------- |
   | CCF ranking     | base   | A=100, B=70, C=40                 |
   | JCR quartile    | base   | Q1=80, Q2=60, Q3=40, Q4=20       |
   | CAS quartile    | base   | 1=90, 2=70, 3=50, 4=30           |
   | Impact factor   | 30%    | IF * 5 (cap 50)                   |
   | Citation count  | 20%    | log10(citations+1) * 10 (cap 50) |
   | Year            | 10%    | max(0, (year-2015) * 2) (cap 30) |
   | Author h-index  | 10%    | first author h-index * 2 (cap 30) |

   ```
   base_score = max(CCF, JCR, CAS)        # highest applicable base, 0 if none
   weighted   = IF*0.3 + citations*0.2 + year*0.1 + h_index*0.1
   penalty    = -20 if (arXiv AND citations < 100) else 0
   total      = base_score + weighted + penalty
   ```

### Step 5: Rank and present

Sort papers by composite score (descending). Present to user:

For each paper:
- **Title** (year) — venue
- Authors (first 3)
- Citations: N | Quality: CCF-A / Q1 / etc.
- Score: X.X | Source: found in S2, AlphaXiv
- arXiv status (if applicable)
- Abstract (first 200 chars)

### Step 6: Save to workspace

Save results to `.research-workspace/sessions/{topic-slug}-{date}/discover.json`:
```json
{
  "query": "...",
  "timestamp": "...",
  "total_found": 42,
  "results": [{ "paper_id": "...", "title": "...", "score": 85.3, ... }]
}
```

### Step 7: Expansion options

After presenting results, offer the user:
- "Want to find papers that cite [paper X]?" → `s2_citations.sh`
- "Want to trace references of [paper X]?" → `s2_references.sh`
- "Want recommendations based on these papers?" → `s2_recommend.sh` with top paper IDs as positives
- "Ready to triage?" → proceed to triage phase
