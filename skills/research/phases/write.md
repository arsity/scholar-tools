# Write Phase

Full conference paper section writing with verified citations.

## Trigger

Called via `/research write <section>` where section is: abstract, introduction, related-work, method, experiments, conclusion, discussion, or any custom section name.

## Output Format Detection

Auto-detect based on workspace context:

1. **LaTeX workspace detected**: check current working directory and parents for `*.tex` or `*.bib` files. If found → output LaTeX directly, no confirmation needed.
2. **Otherwise**: ask user to choose — LaTeX, Markdown, or Notion (via Notion MCP).

## Context Sources

Read the user's own content from:
- `.tex` files from overleaf git clone (if present)
- Prior survey/read/cite results from `.research-workspace/`
- Notion pages (if user specifies, via Notion MCP)
- User's direct instructions and notes

## Workflow

### Step 1: Gather context

1. Check for `.tex` files in workspace — read existing draft sections
2. Load relevant read analyses from `.research-workspace/sessions/*/read/`
3. Load cite-log for already-verified citations
4. Understand the paper's positioning from discover/triage results

### Step 2: Invoke ml-paper-writing skill

Use the `ml-paper-writing` skill (from Orchestra-Research AI-Research-SKILLs plugin) for:
- Paper structure conventions for the target venue
- Section-specific writing guidelines
- Common patterns for ML/AI papers

### Step 3: Write the section

Generate the requested section following academic conventions:
- Clear, concise prose
- Proper citation format (`\cite{key}` for LaTeX)
- Logical flow and argumentation
- Quantitative claims backed by data from read analyses

### Step 4: Verify all citations

**Every `\cite{key}` in the output must be verified through the cite phase.**

For each citation reference in the written text:
1. Check cite-log — if already verified, use existing BibTeX
2. If not verified — run cite phase for that paper
3. If cite phase fails — flag the citation and ask user

No unverified citations in the final output.

### Step 5: Style review

Invoke the `humanizer` skill to review the written text for:
- AI writing patterns to remove
- Natural academic voice
- Clarity and conciseness

### Step 6: Present to user

Show the written section with:
- The full text (LaTeX or Markdown)
- List of citations used (with source tags)
- Any flagged issues (unverified citations, uncertain claims)
- Suggested BibTeX entries to add to the `.bib` file

Ask user to review before finalizing.

### Step 7: Output

If LaTeX workspace:
- Show the LaTeX code for the user to paste into their `.tex` file
- Show new BibTeX entries to append to `.bib`

If Markdown:
- Show the formatted markdown
- Show references list at the bottom

If Notion:
- Use Notion MCP to create/update a page with the section content

## Supported Sections

| Section | Key elements |
| --- | --- |
| Abstract | Problem, method, key results, significance |
| Introduction | Motivation, gap, contribution, paper organization |
| Related Work | Organized by sub-topic, compare & contrast, position own work |
| Method | Architecture, loss functions, training procedure, key design choices |
| Experiments | Setup, baselines, metrics, main results, ablations |
| Conclusion | Summary, limitations, future work |
| Discussion | Broader implications, failure analysis, ethical considerations |

## Language

All output in English. For uncommon vocabulary (GRE-level), add Chinese translation in parentheses.
