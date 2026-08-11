#!/usr/bin/env bash
#
# md-to-pdf.sh — convert Markdown notes into nicely formatted PDFs.
#
# Where it runs: anywhere pandoc + xelatex (+ Graphviz `dot` for diagrams) are
# on PATH. That includes the Cowork Linux sandbox any Claude session has, and
# — as of 2026-07-29 — this Mac directly, via the Homebrew installs at
# /opt/homebrew/bin. So it works in ANY future session, local or sandboxed.
#
# Usage (from a session, via bash):
#   bash _scripts/md-to-pdf.sh path/to/note.md [more.md ...]   # specific files
#   bash _scripts/md-to-pdf.sh --all                           # every .md in the tree
#
# Output: a PDF beside each .md (same name, .pdf extension). Existing PDFs are
# overwritten so the PDF always mirrors the current Markdown.

set -euo pipefail

# Base pandoc options.
ARGS=(
  --pdf-engine=xelatex
  --toc --toc-depth=2
  -V geometry:margin=2.2cm
  -V fontsize=11pt
  -V linkcolor=blue
  -V toccolor=black
)

# Use nicer fonts only if present; otherwise fall back to pandoc defaults so the
# script never breaks on a fresh sandbox.
if fc-list 2>/dev/null | grep -qi "Lato"; then ARGS+=(-V mainfont="Lato"); fi
if fc-list 2>/dev/null | grep -qi "Latin Modern Mono"; then ARGS+=(-V monofont="Latin Modern Mono"); fi

# Resolve the folder root (parent of _scripts) so --all scans the whole KB.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Render Graphviz diagram sources (*.dot) to PDF so Markdown can embed them.
# Diagram sources are the source of truth; the PDFs are regenerated mirrors.
if command -v dot >/dev/null 2>&1; then
  while IFS= read -r d; do
    if dot -Tpdf "$d" -o "${d%.dot}.pdf" 2>/dev/null; then echo "diagram: ${d%.dot}.pdf"; fi
  done < <(find "$ROOT" -name '*.dot' -not -path '*/_*')
fi

targets=()
if [[ $# -eq 0 || "${1:-}" == "--all" ]]; then
  # --all converts content notes only: skips CLAUDE.md and anything in or named
  # with a leading underscore (_scripts, _templates, _inbox, _template.md, ...).
  # To force a meta file, pass it explicitly as an argument instead.
  while IFS= read -r f; do targets+=("$f"); done \
    < <(find "$ROOT" -name '*.md' -not -path '*/_*' -not -name 'CLAUDE.md')
else
  targets=("$@")
fi

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No .md files found."; exit 0
fi

fail=0
for md in "${targets[@]}"; do
  if [[ ! -f "$md" ]]; then echo "skip (not found): $md"; continue; fi
  # Run pandoc from the document's own directory so relative image paths
  # (e.g. diagrams/agent-loop.pdf) resolve against the note, not the cwd.
  dir="$(cd "$(dirname "$md")" && pwd)"
  base="$(basename "$md")"
  pdf="${base%.md}.pdf"
  if ( cd "$dir" && pandoc "$base" -o "$pdf" "${ARGS[@]}" ) 2>/tmp/md2pdf.err; then
    echo "built: $dir/$pdf"
  else
    echo "FAILED: $md"; sed 's/^/    /' /tmp/md2pdf.err; fail=1
  fi
done
exit $fail
