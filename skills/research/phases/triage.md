# Triage Phase

Quick screening of discovered papers to decide which deserve deep reading.

## Trigger

Called after discover phase, or directly via `/research triage` on a set of papers.

## Input

Papers from discover results (`.research-workspace/sessions/{slug}/discover.json`), or paper IDs provided by the user.

## Workflow

### Step 1: Load discover results

Read the current session's `discover.json`. Present the ranked list to the user if not already shown.

### Step 2: For each paper, fetch quick overview

Process papers in order of composite score (highest first).

**For arXiv papers:**

1. Try AlphaXiv MCP `get_paper_content` (report/overview mode)
2. If MCP unavailable: `curl -s "https://alphaxiv.org/overview/{arxiv_id}.md"`
3. If alphaxiv returns 404: use S2 abstract from discover results

**For non-arXiv papers (conference-only):**

1. Check S2 `openAccessPdf` URL from discover results
2. If available: download and read the PDF directly
3. If not: resolve DOI to publisher page:
   - CVF Open Access for CVPR/ICCV/ECCV papers
   - ACM Digital Library for ACM papers
   - IEEE Xplore for IEEE papers
4. Read the paper's abstract and introduction

### Step 3: Generate relevance verdict

For each paper, produce:
- **Verdict**: 1-2 sentences on relevance to the user's query
- **Key contribution**: what this paper adds to the field
- **Quality tier**: from discover score (A/B/C mapping)
- **Read recommendation**: "Must read" / "Worth reading" / "Skim" / "Skip"

### Step 4: Present to user

Display as a ranked list:

```
1. [Must read] Title (Year) — Venue
   Verdict: ...
   Key contribution: ...
   Score: X.X | Citations: N

2. [Worth reading] Title (Year) — Venue
   ...
```

Ask user: "Which papers would you like to read in depth? (e.g., 1, 3, 5 or 'all must-reads')"

### Step 5: Save triage results

Save to `.research-workspace/sessions/{slug}/triage.json`:
```json
{
  "timestamp": "...",
  "papers": [
    {
      "paper_id": "...",
      "verdict": "...",
      "recommendation": "must_read",
      "key_contribution": "..."
    }
  ]
}
```

### Step 6: Route selected papers to read phase

Pass user's selections to the read phase.
