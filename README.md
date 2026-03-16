# research-skill

A Claude Code plugin for academic research. `/research survey "topic"` searches multiple databases in parallel, ranks papers by venue quality and citations, and lets you deep-read the ones that matter. `/research cite` generates verified BibTeX. Every citation traces to an API call, never to model memory.

<p>
  <img src="https://img.shields.io/badge/Claude_Code-black?style=flat-square&logo=anthropic&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

## What it does

| Command | What happens |
|---------|-------------|
| `/research survey "topic"` | Parallel search across Semantic Scholar + HF + AlphaXiv, deduplicate, score by venue/citations/h-index, triage, then deep-read selected papers |
| `/research discover "topic"` | Search only — multi-source discovery with quality ranking |
| `/research triage` | Quick-screen candidates from a previous discovery |
| `/research read 2401.12345` | Deep structured analysis of a single paper |
| `/research cite 2401.12345` | Verified BibTeX via DBLP > CrossRef > S2 chain |
| `/research cite "paper title"` | Same, by title lookup |
| `/research write introduction` | Write a paper section with verified citations (LaTeX/Markdown) |
| `/research trending` | Personalized digest of today's trending papers |

## How search works

Three agents run in parallel, each with a 60-second timeout:

1. **Semantic Scholar** — relevance search (`s2_search.sh`) + boolean bulk search (`s2_bulk_search.sh`) with year filtering
2. **AlphaXiv MCP** — embedding similarity + full-text keyword search
3. **Hugging Face MCP** — `paper_search` semantic search

Results are deduplicated by arXiv ID / DOI / title similarity, then scored:

| Signal | Weight |
|--------|--------|
| CCF ranking (A/B/C) | base score |
| JCR/CAS quartile | base score |
| Impact factor | 30% |
| Citation count (log-scaled) | 20% |
| Recency | 10% |
| First-author h-index | 10% |

arXiv-only papers with < 100 citations get a -20 penalty. Published versions are preferred.

Optional expansion: citation graph traversal (`s2_citations.sh`, `s2_references.sh`) and recommendation (`s2_recommend.sh`).

## How citations work

Zero hallucination policy. Every BibTeX entry must trace to an API response. The chain:

```
1. DBLP search → title match (>90% token overlap) → fetch .bib        → "via DBLP"
2. CrossRef search → extract DOI → content negotiation                 → "via CrossRef"
3. S2 exact match → construct from metadata                            → "via S2 — verify manually"
4. All fail → "Citation source not verified. Not safe to cite."
```

Never generates BibTeX from model memory. Never fills in year/venue/authors from model knowledge.

## Installation

### Claude Code

```bash
# Install via plugin marketplace
claude plugin install research-skill@arsity

# Or manual install
git clone https://github.com/arsity/research-skill.git ~/.claude/plugins/research-skill
```

### Prerequisites

**Required:**

1. **Semantic Scholar API key** — get one at [semanticscholar.org/product/api](https://www.semanticscholar.org/product/api/api-key), then:
   ```bash
   cp skills/research/.env.example skills/research/.env
   # Edit .env and add your S2_API_KEY
   ```

2. **Required plugins:**
   - `tanwei/pua` — provides `high-agency` and `pua-en` skills
   - `Orchestra-Research/AI-Research-SKILLs` — provides `ml-paper-writing` skill
   - A `humanizer` skill for style review during paper writing

**Optional MCP servers:**

- **AlphaXiv MCP** — endpoint `https://api.alphaxiv.org/mcp/v1` (SSE + OAuth 2.0). Gives direct access to paper overviews and full text. Without it, the skill uses `curl` against the public alphaxiv.org endpoints instead.
- **Hugging Face MCP** — adds HF as a third search source. Without it, discovery runs on S2 + AlphaXiv only.

Without MCP servers, citations and quality evaluation still work. You just get fewer search sources during discovery.

## Project structure

```
skills/research/
  SKILL.md                  # Orchestrator — intent detection + routing
  .env.example              # API key template
  phases/
    discover.md             # Multi-source parallel search + merge + quality eval
    triage.md               # Quick screening via AlphaXiv overviews
    read.md                 # Deep structured analysis
    cite.md                 # DBLP > CrossRef > S2 BibTeX chain
    write.md                # Paper section writing (LaTeX/Markdown/Notion)
    trending.md             # Personalized trending digest
  scripts/                  # 18 self-contained bash scripts
    init.sh                 # Env loading, rate limit helpers
    s2_search.sh            # S2 relevance-ranked search
    s2_bulk_search.sh       # S2 boolean bulk search with year filtering
    s2_batch.sh             # S2 batch metadata (up to 500 IDs)
    s2_citations.sh         # Citation graph traversal
    s2_references.sh        # Reference graph traversal
    s2_recommend.sh         # Paper recommendations
    s2_snippet.sh           # Search within paper bodies
    s2_match.sh             # Exact title match
    dblp_search.sh          # DBLP publication search
    dblp_bibtex.sh          # DBLP key → .bib
    crossref_search.sh      # CrossRef search
    doi2bibtex.sh           # DOI → BibTeX via content negotiation
    hf_daily_papers.sh      # HF trending papers API
    venue_info.sh           # Venue quality summary (CCF + IF + quartile)
    ccf_lookup.sh           # CCF ranking lookup
    if_lookup.sh            # Impact factor lookup
    author_info.sh          # Author h-index and stats
  data/
    ccf_2026.sqlite         # CCF rankings database (682 entries)
    ccf_2026.jsonl          # CCF rankings source
    impact_factor.sqlite3   # Impact factor database (19,727 journals)
  tests/                    # 8 test suites + runner
    run_all_tests.sh
    test_s2_search.sh
    test_s2_network.sh
    test_s2_batch.sh
    test_dblp.sh
    test_crossref.sh
    test_quality_eval.sh
    test_hf_daily.sh
    test_cite_chain.sh
```

## Running tests

```bash
bash skills/research/tests/run_all_tests.sh
```

Requires a Semantic Scholar API key in `skills/research/.env`. Tests hit live APIs (S2, DBLP, CrossRef, HF).

## Workspace

On first invocation, `/research` creates `.research-workspace/` in the current directory. Each survey gets its own session with discover results, triage verdicts, read analyses, and verified BibTeX — all persisted as JSON for reuse across phases.

```
.research-workspace/
  state.json
  sessions/
    {topic-slug}-{date}/
      discover.json
      triage.json
      read/{paper_id}.json
      cite/{paper_id}.bib
      cite/cite-log.json
```

## Rate limits

| Service | Limit | Strategy |
|---------|-------|----------|
| Semantic Scholar | 1 req/sec (with key) | Sequential + batch/bulk endpoints |
| DBLP | ~1 req/sec | Sequential, 1s delay |
| CrossRef | 50 req/sec | Polite pool |
| HF / AlphaXiv MCP | No strict limit | Respectful usage |

## License

[MIT](LICENSE) — Luke (Haopeng Chen)
