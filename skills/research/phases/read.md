# Read Phase

Deep analysis of selected papers.

## Trigger

Called after triage, or directly via `/research read 2401.12345` or `/research read "paper title"`.

## Workflow

### Step 1: Resolve paper identity

If given an arXiv ID: use directly.
If given a title: use `s2_match.sh` to find the S2 paper ID and arXiv ID.
If given a DOI: look up via CrossRef or S2.

### Step 2: Fetch full paper content

Follow this fallback chain (stop at the first that provides sufficient content):

1. **AlphaXiv MCP `get_paper_content`** (report mode) — own Claude analyzes the structured report
2. **AlphaXiv MCP `get_paper_content`** (full text / raw markdown) — if report lacks detail, get full text
3. **AlphaXiv curl fallback** — if MCP unavailable:
   - `curl -s "https://alphaxiv.org/overview/{ID}.md"` (overview)
   - `curl -s "https://alphaxiv.org/abs/{ID}.md"` (full text)
4. **arXiv PDF** — download from `https://arxiv.org/pdf/{ID}` and read directly
5. **Conference/publisher PDF** — for non-arXiv papers:
   - S2 `openAccessPdf` field
   - CVF Open Access (CVPR/ICCV/ECCV)
   - ACM Digital Library
   - IEEE Xplore

**Never use AlphaXiv's `answer_pdf_queries`** — we do not control their model.

### Step 3: Appendix / supplementary material

arXiv versions often omit appendices. When:
- The user asks about details not in the main text (ablation tables, proofs, hyperparameters)
- The text references supplementary material not included

Fetch the published conference version:
1. Check S2 `openAccessPdf` for the published version
2. Resolve DOI to publisher page
3. Download and read the full published PDF including appendix

### Step 4: Additional tools during read

- **Code inspection**: AlphaXiv MCP `read_files_from_github_repository` if the paper has an associated repo
- **Cross-paper evidence**: `s2_snippet.sh` to find specific claims or methods across papers. Use when: the user questions a claim, or you need corroborating evidence.

### Step 5: Produce structured analysis

For each paper, output:

```markdown
## [Title] (Year) — Venue

### Research Question & Motivation
What problem does this paper address? Why does it matter?

### Methodology
Key techniques, architecture, loss functions, training details.

### Main Findings
Quantitative results, comparisons with baselines, key numbers.

### Limitations & Failure Cases
What doesn't work? What are the assumptions?

### Relevance to Your Research
How does this connect to [user's research areas]?

### Key Equations/Tables
(If requested or particularly important)
```

For uncommon technical terms (GRE-level), add Chinese translation in parentheses.

### Step 6: Save read results

Save to `.research-workspace/sessions/{slug}/read/{paper_id}.json`:
```json
{
  "paper_id": "...",
  "title": "...",
  "content_source": "alphaxiv_mcp|alphaxiv_curl|arxiv_pdf|publisher_pdf",
  "analysis": {
    "research_question": "...",
    "methodology": "...",
    "findings": "...",
    "limitations": "...",
    "relevance": "..."
  }
}
```

### Step 7: Follow-up options

After presenting the analysis:
- "Want to cite this paper?" → route to cite phase
- "Want to find papers that cite this one?" → `s2_citations.sh`
- "Want to check specific claims in other papers?" → `s2_snippet.sh`
- "Want to read another paper?" → loop back
