# Research Skill Design Spec

## Overview

A unified `/research` skill for the full academic research lifecycle: discovery, triage, deep reading, citation management, paper writing, and trend monitoring. Single entry point with subcommands, modular phase architecture, parallel search agents where applicable.

## Architecture

```
skills/research/
  SKILL.md                  # Orchestrator: intent detection, high-agency preload, routing
  phases/
    discover.md             # Parallel search (S2 + AlphaXiv MCP + HF MCP) → merge → quality eval → rank
    triage.md               # AlphaXiv MCP overview for quick screening
    read.md                 # Deep read via AlphaXiv MCP full text, own Claude analyzes
    cite.md                 # DBLP > CrossRef > S2 BibTeX chain + quality eval + verification
    write.md                # Full paper writing (all sections) → LaTeX
    trending.md             # HF daily_papers + AlphaXiv hot → personalized digest
  scripts/
    # Search
    s2_search.sh            # S2 relevance-ranked semantic search, ≤100/page, 1000 max (copy from citation-assistant)
    s2_bulk_search.sh       # S2 boolean search (+,|,-,""), ≤1000/call, 10M via pagination, sortable (copy from citation-assistant)
    s2_citations.sh         # NEW: GET /paper/{id}/citations
    s2_references.sh        # NEW: GET /paper/{id}/references
    s2_recommend.sh         # NEW: POST /recommendations/v1/papers/
    s2_batch.sh             # NEW: POST /paper/batch — NOT a search; takes known IDs, returns metadata (up to 500)
    s2_snippet.sh           # NEW: GET /snippet/search
    s2_match.sh             # NEW: GET /paper/search/match
    dblp_search.sh          # NEW: DBLP publication search API
    dblp_bibtex.sh          # NEW: DBLP key → .bib fetch
    crossref_search.sh      # CrossRef search (copy from citation-assistant)
    hf_daily_papers.sh      # NEW: curl HF daily_papers API
    # Quality evaluation
    author_info.sh          # S2 author h-index lookup (copy from citation-assistant)
    venue_info.sh           # Venue quality lookup (copy from citation-assistant)
    ccf_lookup.sh           # CCF ranking lookup (copy from citation-assistant)
    if_lookup.sh            # Impact factor lookup (copy from citation-assistant)
    # BibTeX
    doi2bibtex.sh           # DOI → BibTeX via CrossRef (copy from citation-assistant)
    # Config
    init.sh                 # Env loading (copy from citation-assistant)
```

All scripts are self-contained copies. No dependency on citation-assistant skill.

## Entry Point

`/research <intent>` — orchestrator parses intent and routes to the appropriate phase.

| Input pattern                    | Phase flow                        |
| -------------------------------- | --------------------------------- |
| `/research survey "topic"`       | discover → triage → read          |
| `/research read 2401.12345`      | read                              |
| `/research cite 2401.12345`      | cite                              |
| `/research write abstract`       | write (LaTeX)                     |
| `/research write introduction`   | write (LaTeX)                     |
| `/research write related-work`   | write (LaTeX)                     |
| `/research write method`         | write (LaTeX)                     |
| `/research write experiments`    | write (LaTeX)                     |
| `/research write conclusion`     | write (LaTeX)                     |
| `/research write discussion`     | write (LaTeX)                     |
| `/research write <section>`      | write (LaTeX, any section)        |
| `/research trending`             | trending                          |
| Ambiguous input                  | Ask user to clarify               |

On every invocation, the orchestrator:
1. Preloads the `high-agency` skill (from `pua@pua-skills` plugin) before routing
2. Checks AlphaXiv MCP connectivity — if unavailable, phases degrade to curl-based fallbacks (see Degraded Mode below)

### Degraded mode (AlphaXiv MCP unavailable)

If AlphaXiv MCP is not connected or unreachable:
- **Discover**: runs only S2 + HF agents (2 of 3)
- **Triage**: falls back to `curl -s "https://alphaxiv.org/overview/{ID}.md"`
- **Read**: falls back to `curl -s "https://alphaxiv.org/abs/{ID}.md"`, then PDF
- **Trending**: AlphaXiv source skipped, HF daily papers only

### Timeout and failure policy

Each parallel search agent has a 60-second timeout. If an agent times out or errors, proceed with results from the remaining agents. Log the failure but do not block the merge step.

## Phase 1: Discover (`discover.md`)

### Search — three parallel agents

**Agent 1: Semantic Scholar**
- `s2_search.sh` for relevance-ranked results
- `s2_bulk_search.sh` for broader boolean queries with year filtering
- All S2 calls sequential within this agent (1 req/sec rate limit)
- Use bulk/batch endpoints to minimize total requests

**Agent 2: AlphaXiv MCP**
- `embedding_similarity_search` for semantic search
- `full_text_papers_search` for keyword search
- `agentic_paper_retrieval` (beta) for multi-turn retrieval when needed

**Agent 3: Hugging Face MCP**
- `mcp__claude_ai_Hugging_Face__paper_search` (semantic search, up to 12 results)

### Merge

A merge agent receives results from all three search agents and:
1. Deduplicates by arXiv ID, then DOI, then title similarity
2. Normalizes metadata format across sources
3. Passes deduplicated list to quality evaluation

### Quality evaluation

For each paper in the merged list:

1. **Batch metadata fetch**: `s2_batch.sh` to get citation count, venue, authors. Chunks requests into groups of at most 500 IDs with 1-second delays between chunks.
2. **Venue quality**: `ccf_lookup.sh`, `if_lookup.sh`, `venue_info.sh`
3. **Author quality**: `author_info.sh` for first author h-index
4. **arXiv classification**:
   - `recommended`: arXiv paper with citations >= 100
   - `caution`: arXiv paper with citations < 100 (flag, lower priority)
   - `normal`: formally published
5. **Composite score**:

| Dimension       | Weight | Calculation                            |
| --------------- | ------ | -------------------------------------- |
| CCF ranking     | base   | A=100, B=70, C=40                      |
| JCR quartile    | base   | Q1=80, Q2=60, Q3=40, Q4=20            |
| CAS quartile    | base   | 1=90, 2=70, 3=50, 4=30                |
| Impact factor   | 30%    | IF * 5 (cap 50)                        |
| Citation count  | 20%    | log10(citations+1) * 10 (cap 50)       |
| Year            | 10%    | max(0, (year-2015) * 2) (cap 30)      |
| Author h-index  | 10%    | first author h-index * 2 (cap 30)     |

**Scoring formula:**
```
base_score = max(CCF, JCR, CAS)        # highest applicable base, 0 if none
weighted   = IF*0.3 + citations*0.2 + year*0.1 + h_index*0.1
# base_score is additive (not scaled); it dominates when present
penalty    = -20 if (arXiv AND citations < 100) else 0
total      = base_score + weighted + penalty
```

Papers with a formally published version are preferred over arXiv-only.

### Expansion (optional, user-triggered)

- `s2_citations.sh`: find papers that cited a key result
- `s2_references.sh`: trace foundational work a paper builds on
- `s2_recommend.sh`: given a set of relevant papers (positive) and irrelevant papers (negative), find what's missing

### Output

Ranked list with per-paper quality report. Saved to persistent workspace file for use by later phases.

## Phase 2: Triage (`triage.md`)

For each candidate paper from discover:

1. Fetch AlphaXiv MCP `get_paper_content` (report/overview mode)
2. If paper not on arXiv (conference-only publication) → resolve via S2 `openAccessPdf` URL or publisher/conference page (e.g., CVF Open Access for CVPR/ICCV/ECCV, ACM DL, IEEE Xplore) → own Claude reads PDF
3. Own Claude generates a 1-2 sentence relevance verdict
4. Present to user with quality score

User decides which papers to deep read. Triage results saved to workspace.

## Phase 3: Read (`read.md`)

Deep analysis of selected papers.

### Content access fallback chain

1. AlphaXiv MCP `get_paper_content` (report mode) → own Claude analyzes
2. If insufficient detail → AlphaXiv MCP `get_paper_content` (full text / raw markdown) → own Claude analyzes
3. If MCP unavailable → `curl -s "https://alphaxiv.org/overview/{ID}.md"` then `curl -s "https://alphaxiv.org/abs/{ID}.md"` → own Claude analyzes
4. If still insufficient → download PDF from `https://arxiv.org/pdf/{ID}` → own Claude reads directly
5. If paper not on arXiv (conference-only) → resolve via S2 `openAccessPdf` field or publisher/conference page → own Claude reads PDF

### Appendix / supplementary material access

arXiv versions often omit appendices that appear in the published conference version. When:
- The user asks about details not found in the arXiv text (e.g., ablation tables, proof details, hyperparameters), OR
- The main text references a supplementary/appendix that is not included

Then fetch the published version from the conference/publisher page:
- Use S2 `openAccessPdf` field if available
- Otherwise resolve DOI to publisher page (CVF Open Access for CVPR/ICCV/ECCV, ACM DL, IEEE Xplore, etc.)
- Download and read the full published PDF including appendix

No use of AlphaXiv's `answer_pdf_queries` — we do not control their model or its quality.

### Additional tools during read

- AlphaXiv MCP `read_files_from_github_repository` for code inspection
- `s2_snippet.sh` for locating specific claims or methods across papers. Usage: when the user questions a specific claim, use snippet search with the claim text to find corroborating or contradicting evidence in other papers.

Output per paper (structured analysis):
- Research question and motivation
- Methodology (key techniques, architecture, loss functions)
- Main findings and quantitative results
- Limitations and failure cases
- Relevance to user's own research
- Key equations/tables (if requested)

Read results saved to workspace.

## Phase 4: Cite (`cite.md`)

Verified BibTeX generation with strict source chain:

```
For each paper:
  1. dblp_search.sh (title query) → check top result title similarity (>90% token overlap)
     Match → dblp_bibtex.sh (fetch https://dblp.org/rec/{KEY}.bib)
     Done, tag "via DBLP"
  2. crossref_search.sh (title or DOI) → doi2bibtex.sh
     Done, tag "via CrossRef"
  3. s2_match.sh (exact title match) → construct BibTeX from S2 metadata
     Done, tag "via S2"
  4. All fail → report "unverified source — not safe to cite"
```

**DBLP matching strategy**: search DBLP with the paper title. Tokenize both titles by splitting on whitespace and lowercasing (word-level, case-insensitive). If the top result's title has >90% token overlap (intersection / union) with the target title, use that DBLP key. If multiple results exceed the threshold, prefer the one with matching year and first author. Otherwise treat as not found and fall through to CrossRef.

**S2-constructed BibTeX caveat**: BibTeX entries constructed from S2 metadata (step 3) are less reliable than DBLP or CrossRef entries. S2 metadata is aggregated and may have venue name inconsistencies or incomplete page numbers. These entries should be flagged with "via S2 — verify manually" in the output.

Quality evaluation attached to each BibTeX entry. Source tag included in output.

### Iron rules

- Every citation must trace to an API call response
- Never generate BibTeX from model memory
- Never fill in metadata (year, venue, authors) from model knowledge
- If all sources fail, report explicitly — do not guess

## Phase 5: Write (`write.md`)

Full conference paper section writing.

### Output format detection

The skill auto-detects output format based on workspace context:

1. **LaTeX workspace detected** (`.tex` files present, e.g., overleaf git clone) → output LaTeX directly, no confirmation needed
2. **Otherwise** → ask user to choose: LaTeX, Markdown, or Notion (via Notion MCP)

Detection logic: check current working directory and parent for `*.tex` or `*.bib` files. If found, assume LaTeX workspace.

### Context sources

The skill reads the user's own content from the workspace:
- `.tex` files from overleaf git clone
- Notion pages (if user specifies, via Notion MCP)
- Prior survey/read/cite results from the persistent workspace

### Supported sections

- Abstract
- Introduction
- Related work
- Method / approach
- Experiments / evaluation
- Any other section the user requests

### Tool integration

- Invokes `ml-paper-writing` skill for paper structure and conventions
- Invokes `humanizer` skill for style review
- Every `\cite{}` routed through cite phase for verification
- User reviews and confirms before output is finalized

## Phase 6: Trending (`trending.md`)

### Sources (parallel where possible)

| Source           | Method                                                        |
| ---------------- | ------------------------------------------------------------- |
| HF Daily Papers  | `hf_daily_papers.sh` (curl `https://huggingface.co/api/daily_papers`) |
| AlphaXiv Hot     | AlphaXiv MCP `embedding_similarity_search` with broad topic query + recency preference; fallback to curl `https://alphaxiv.org/?sort=Hot&subcategories={subcategory}` and parse. Default subcategory: `computer-vision`. Parameterized based on user's research profile. |

### Personalization filter

Based on user's research profile, each paper tagged:

| Tier   | Criteria                                                              |
| ------ | --------------------------------------------------------------------- |
| High   | pose estimation, low-visibility, AIGC, VLM/MLLM, multimodal          |
| Medium | general CV, image generation, video understanding, robotics + vision  |
| Low    | pure text LLM, NLP-only, non-vision tasks                            |

High-relevance papers sorted to top. Low-relevance papers grouped at bottom but not hidden.

### Output

Curated digest per paper:
- Title, authors, date
- 1-2 sentence summary (from HF AI summary or AlphaXiv overview)
- Relevance tier + reasoning
- Link to full overview
- Potential connection to user's research (for high-relevance papers)

## State Persistence

Survey results, quality evaluations, triage verdicts, read analyses, and BibTeX entries are saved to a persistent workspace directory. Subsequent phase invocations reference this state.

### Workspace structure

```
.research-workspace/
  state.json                # Master index: { sessions: [...], current_session: "..." }
  sessions/
    {topic-slug}-{date}/
      discover.json         # { query, results: [{ paper_id, title, score, source, ... }] }
      triage.json            # { papers: [{ paper_id, verdict, relevance, ... }] }
      read/
        {paper_id}.json     # { paper_id, analysis: { question, method, findings, ... } }
      cite/
        {paper_id}.bib      # Verified BibTeX entry
        cite-log.json       # { entries: [{ paper_id, source_tag, timestamp }] }
```

Papers are linked across phases by `paper_id` (arXiv ID preferred, DOI as fallback).

The `.research-workspace/` directory is created in the current working directory by the orchestrator on first invocation if it does not exist.

This is conversation-local persistence, not cross-session memory. For cross-session information, use the memory system.

## Iron Rules

1. **Zero hallucination citations** — every citation from an API call, never from model memory
2. **BibTeX priority** — DBLP > CrossRef > S2 > AlphaXiv (AlphaXiv is content-only, not a citation source)
3. **High-agency preload** — loaded at skill start, drives exhaustive search and retry
4. **Quality gate** — no paper presented to user without quality evaluation
5. **Source tracing** — every citation tagged with data source ("via DBLP", "via CrossRef", etc.)
6. **Own model for analysis** — never rely on AlphaXiv's AI-generated answers; use their content extraction, analyze with own Claude

## Language

All output in English. For uncommon vocabulary (GRE-level), add Chinese translation in parentheses.

## Dependencies

This skill depends on the following external skills/plugins. **No other skills/plugins are expected to be installed.** The skill is self-contained for everything else (all scripts copied in, no references to other skills).

### Required skill/plugin dependencies

| Dependency | Source | What it provides |
| --- | --- | --- |
| `high-agency` | `tanwei/pua` plugin | Pre-loaded at skill start for exhaustive retry behavior |
| `pua-en` | `tanwei/pua` plugin | Pressure escalation when stuck |
| `ml-paper-writing` | `Orchestra-Research AI-Research-SKILLs` plugin | Paper structure and conventions for write phase |
| `humanizer` | `humanizer` skill | Style review for write phase |

### Required MCP servers (user must configure)

| MCP Server | Setup |
| --- | --- |
| **AlphaXiv MCP** | Add to Claude Code MCP config. Endpoint: `https://api.alphaxiv.org/mcp/v1`, Transport: SSE + OAuth 2.0 |
| **HF MCP** | Hugging Face MCP (connected as user 'arsity' if using claude.ai) |

### Required API keys (user must obtain)

| Key | Setup |
| --- | --- |
| **Semantic Scholar API key** | Save to `skills/research/.env` as `S2_API_KEY`. Obtain from: https://www.semanticscholar.org/product/api/api-key. Without key: shared rate limit, frequent 429 errors. With key: 1 req/sec dedicated limit. |

### Optional

- Notion MCP (for outputting survey reports or reading raw discussion notes)
- Overleaf git workspace (for write phase to read/write .tex files)

### Installation prompt

On first invocation, if dependencies are missing, the skill should prompt the user:

```
Before using /research, please ensure the following are set up:

1. Install required plugins:
   - tanwei/pua (provides high-agency, pua-en skills)
   - Orchestra-Research AI-Research-SKILLs (provides ml-paper-writing skill)
   - humanizer skill

2. Configure MCP servers:
   - AlphaXiv MCP: endpoint https://api.alphaxiv.org/mcp/v1 (SSE + OAuth)
   - HF MCP: Hugging Face integration

3. Set up API keys:
   - Semantic Scholar: save S2_API_KEY in skills/research/.env
     Get your key at: https://www.semanticscholar.org/product/api/api-key
```

## Tool preference

- MCP over curl when MCP provides richer or more structured functionality
- curl acceptable when no MCP equivalent exists (DBLP, HF daily_papers, S2 scripts)
- Scripts for S2 interactions (well-tested, rate-limit-aware, already built)

## Rate limits

| Service    | Rate limit                    | Strategy                                    |
| ---------- | ----------------------------- | ------------------------------------------- |
| S2         | 1 req/sec (with API key)      | Sequential within Agent 1, use batch/bulk   |
| DBLP       | ~1 req/sec (undocumented)     | Sequential, 1-second delay between calls    |
| CrossRef   | 50 req/sec (with polite pool) | Include `mailto` param for polite pool      |
| HF MCP     | No strict limit               | Respect reasonable usage                    |
| AlphaXiv MCP | Unknown                     | Respect reasonable usage, retry on failure  |

## API base URLs

| Service            | Base URL                                              |
| ------------------ | ----------------------------------------------------- |
| S2 Academic Graph  | `https://api.semanticscholar.org/graph/v1`            |
| S2 Recommendations | `https://api.semanticscholar.org/recommendations/v1`  |
| DBLP Search        | `https://dblp.org/search/publ/api`                    |
| DBLP BibTeX        | `https://dblp.org/rec/{KEY}.bib`                      |
| CrossRef           | `https://api.crossref.org/works`                      |
| HF Daily Papers    | `https://huggingface.co/api/daily_papers`             |
| AlphaXiv Overview  | `https://alphaxiv.org/overview/{ID}.md`               |
| AlphaXiv Full Text | `https://alphaxiv.org/abs/{ID}.md`                    |
| AlphaXiv MCP       | `https://api.alphaxiv.org/mcp/v1`                     |

## Script language note

All scripts are bash. Copied scripts from citation-assistant output in JSON format. New scripts follow the same pattern. Script output language is English (the original citation-assistant scripts output Chinese report headers like "引用推荐报告" — these are not copied; the research skill handles all reporting in its own output layer in English).
