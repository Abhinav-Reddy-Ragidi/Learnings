# CLAUDE.md

Operating instructions for managing Abhinav's knowledge base. Read fully before acting.

## Purpose
1. **Learning** — file notes, resources, and practice for topics being studied.
2. **Work skills** — keep a skills matrix tied to real project evidence, for showcasing capability.

## Map
- `AI-ML-Data/` — subject track. Topic = `<topic>/` holding one consolidated `<topic>.md` + `diagrams/`, and optional `resources/`, `practice/`. Sub-topics nest as a child folder with the same shape (e.g. `ai-models/` → `ai-models/llms/`).
- `Work-Skills/` — `SKILLS-MATRIX.md` + `README.md`. Also currently hosts `Programming-Tech/` topic notes (they began as work evidence and grew into topic notes); a new *purely* learning-side programming topic can go in a top-level `Programming-Tech/` instead.
- `INDEX.md` — topic list, the entry point for finding a note.
- `_scripts/md-to-pdf.sh` — reusable converter (pandoc+xelatex + Graphviz). Works locally on the Mac and in any session sandbox.
- Not created yet, add when first needed: `_templates/` (blanks), `_inbox/` (unfiled captures).

## Conventions
- Files & folders: `lowercase-with-hyphens`, descriptive name, **no date in the filename** (put the date inside the file's metadata instead). `_`-prefixed = meta.
- Prefer **one consolidated document per topic** for easy revision; only split into multiple files when a topic genuinely grows too large.
- **Use diagrams generously.** Every learning note should include enough diagrams to make it easy to consume — add one for any loop, flow, hierarchy, layering, or multi-part relationship. Author each as a Graphviz `.dot` file in a `diagrams/` subfolder beside the note and embed the rendered PDF: `![caption](diagrams/name.pdf){ width=85% }`. `_scripts/md-to-pdf.sh` renders every `.dot` to PDF automatically, so the `.dot` is the source of truth.
- **Check diagram shape, not just correctness.** A `.dot` that renders "fine" can still be unreadable on the page. Aim for an aspect ratio between roughly 0.8 and 2.5, then set `width=` to suit: wide diagrams get `width=100%`, tall ones need `width=55–70%` or they overflow the text area. Check with `dot -Tpng -Gdpi=100 x.dot -o /tmp/x.png` and read the pixel dimensions.
  - Long linear chain rendering as an unreadable sliver → split into two rows *serpentine-style*: break the chain with `constraint=false` on one edge so the rest starts a new row.
  - Several independent panels in one figure → give each its own `subgraph cluster_*` with `rankdir=LR` chains. Note `dot` stacks disconnected components **bottom-up**, so declare the clusters in reverse order to get top-down reading order (`pack`/`packmode` do not help here).
- Proficiency: **Aware → Practiced → Proficient → Expert**. Above "Practiced" needs a backing project.

## Behaviors
- "I learned X" → file under the right topic (create the topic folder if new; mirror the shape of an existing note), update `INDEX.md`.
- "I did X at work" → add/update a `projects/` entry, update its row in `SKILLS-MATRIX.md`.
- "export the matrix" → regenerate `Work-Skills/Skills-Matrix.xlsx` from the markdown.
- **After creating or editing any content `.md`** → regenerate its PDF so the two stay in sync: `bash _scripts/md-to-pdf.sh <file.md>` (or `bash _scripts/md-to-pdf.sh --all` to rebuild every content PDF). Skip meta files (CLAUDE.md, `_`-prefixed).
- Unsure where it goes → put it in `_inbox/` (create the folder if absent), don't guess. If the ambiguity is *which existing track* it belongs to, ask rather than filing it twice.

## Rules
- Markdown is the source of truth; the `.pdf` (and `.xlsx`) are generated mirrors — never edit them by hand, always regenerate.
- Every content `.md` should have a matching `.pdf` next to it, kept up to date after edits.
- Never store confidential/NDA detail; scrub client/employer info from work entries.
- After changes, update `INDEX.md` and the relevant `_Last updated:` date.
- **Keep this file current**: whenever the folder changes structurally — a new top-level track, a renamed convention, a changed workflow — update this `CLAUDE.md` to match.
