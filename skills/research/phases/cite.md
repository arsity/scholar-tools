# Cite Phase

Verified BibTeX generation with strict source chain. Zero hallucination policy.

## Trigger

Called via `/research cite 2401.12345` or `/research cite "paper title"`, or automatically during write phase for every `\cite{}`.

## Iron Rules

1. **Every citation must trace to an API call response** — never from model memory
2. **Never generate BibTeX from model memory** — always fetch from external source
3. **Never fill in metadata from model knowledge** — year, venue, authors must come from API
4. **If all sources fail** — report "unverified source — not safe to cite", do not guess

## Workflow

### Step 1: Resolve paper identity

If given an arXiv ID: search by ID.
If given a title: search by title.
If given a DOI: use directly for CrossRef.

### Step 2: BibTeX source chain

Execute in order. Stop at the first success.

```
1. DBLP (highest quality)
   → dblp_search.sh "<title>" 5
   → Check top result: tokenize both titles (split whitespace, lowercase)
   → If token overlap > 90% (intersection/union): use that DBLP key
   → If multiple results > 90%: prefer matching year + first author
   → dblp_bibtex.sh "<dblp_key>"
   → Tag: "via DBLP"

2. CrossRef (DOI-based)
   → If DOI known: doi2bibtex.sh "<doi>"
   → If DOI unknown: crossref_search.sh "<title>" 3 → extract DOI → doi2bibtex.sh
   → Tag: "via CrossRef"

3. S2 (last resort, less reliable)
   → s2_match.sh "<title>"
   → Construct BibTeX from S2 metadata (paperId, title, year, venue, authors)
   → Tag: "via S2 — verify manually"
   → ⚠️ S2 metadata may have venue name inconsistencies or missing page numbers

4. All fail
   → Report: "Citation source not verified for: <title>. Not safe to cite."
   → Do NOT generate from model knowledge
```

### DBLP matching strategy

```python
# Pseudocode for title matching
def token_overlap(title_a, title_b):
    tokens_a = set(title_a.lower().split())
    tokens_b = set(title_b.lower().split())
    intersection = tokens_a & tokens_b
    union = tokens_a | tokens_b
    return len(intersection) / len(union)

# Accept if overlap > 0.90
```

### Step 3: Quality evaluation

For each cited paper, attach quality info:
```bash
bash scripts/venue_info.sh "<venue>"
bash scripts/author_info.sh "<first_author_id>"
```

### Step 4: Output format

For each citation:

```
📄 Title (Year) — Venue
Source: via DBLP ✓
Quality: CCF-A | Citations: 1234 | h-index: 45

@inproceedings{He2016DeepRL,
  author    = {Kaiming He and ...},
  title     = {Deep Residual Learning for Image Recognition},
  booktitle = {CVPR},
  year      = {2016},
  ...
}
```

### Step 5: Save citation

Save BibTeX to `.research-workspace/sessions/{slug}/cite/{paper_id}.bib`

Update cite log at `.research-workspace/sessions/{slug}/cite/cite-log.json`:
```json
{
  "entries": [
    {
      "paper_id": "...",
      "title": "...",
      "source_tag": "via DBLP",
      "bibtex_key": "He2016DeepRL",
      "timestamp": "..."
    }
  ]
}
```

### Step 6: Batch citation mode

When citing multiple papers (e.g., from survey results):
- Process all through the chain
- Group results by source tag
- Report any failures prominently at the end
- Output combined .bib file
