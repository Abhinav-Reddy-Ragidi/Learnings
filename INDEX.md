# Index

Topic list for the knowledge base. One line per note; follow the link for the full document.

_Last updated: 2026-08-11_

## AI-ML-Data

| Topic | Note | Covers |
|---|---|---|
| AI Models | [ai-models.md](AI-ML-Data/ai-models/ai-models.md) | What a model is, training vs inference, learning paradigms, discriminative vs generative, model families, foundation-model stack, choosing a model |
| — LLMs | [llms.md](AI-ML-Data/ai-models/llms/llms.md) | Tokens, attention, context window, training stages, decoding controls, **model behaviour → pipeline design**, pipeline patterns, adaptation strategy, evals, cost & latency |

## Programming-Tech

Currently filed under `Work-Skills/Programming-Tech/` (these began as work-evidence notes and grew into topic notes).

| Topic | Note | Covers |
|---|---|---|
| Agentic software development | [agentic-development-handbook.md](Work-Skills/Programming-Tech/agentic-software-development/agentic-development-handbook.md) | Claude Code internals, the agent loop, harness engineering, commands vs agents vs skills |
| Software development | [eng-labs-platform.md](Work-Skills/Programming-Tech/Software%20Development/eng-labs-platform.md) | **Source of truth for the eng-labs monorepo**: system-at-a-glance figures, monorepo/workspace/Turborepo architecture, package dependency graph, runtime topology, multi-tenancy & auth model, request lifecycle, full stack, skills & roles |
| Software development | [multitenant-platform-engineering-lessons.md](Work-Skills/Programming-Tech/Software%20Development/multitenant-platform-engineering-lessons.md) | **Lessons & tracking** for the same codebase: scored self-review, status against the previous review, module depth & information hiding, tradeoffs ledger, improvement roadmap, meta-lessons |
| Multi-tenancy | [multi-tenancy-patterns.md](Work-Skills/Programming-Tech/Software%20Development/multi-tenancy-patterns.md) | **Concepts & revision reference**: the five isolation models compared, decision guide, the four enforcement layers (app → ORM → RLS → instance), the six leak paths, what "tenant" touches beyond the DB, per-model operations, isolation testing, eng-labs case study, prepared interview answers, new-system checklist |
| Infra | [gpu-infrastructure-hosting-open-source-models.md](Work-Skills/Programming-Tech/infra/gpu-infrastructure-hosting-open-source-models.md) | GPU infrastructure for hosting open-source models |

## Work-Skills

| File | Purpose |
|---|---|
| [SKILLS-MATRIX.md](Work-Skills/SKILLS-MATRIX.md) | Skills matrix with proficiency levels and backing project evidence |
| [README.md](Work-Skills/README.md) | How the Work-Skills track is organised |

## Meta

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Operating instructions for maintaining this knowledge base |
| `_scripts/md-to-pdf.sh` | Renders `.dot` diagrams and converts content `.md` to PDF |
