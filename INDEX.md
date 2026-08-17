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
| Multi-tenancy, AuthN & AuthZ | [multi-tenancy.md](Work-Skills/Programming-Tech/Software%20Development/multi-tenancy.md) | **Part I — patterns:** the five isolation models compared, decision guide, shared-schema data modelling, **authentication** (the three questions, session vs token, revocation debt, tenant resolution & trust, context switching, cross-app SSO), **authorization** (the permission-model spectrum, three-gate contract, chokepoints, 401/403/404 leakage, failure modes), the four enforcement layers, the six leak paths, per-model operations, isolation + auth test matrix, 7 interview answers, new-system checklist. **Part II — codebase lessons:** the auth implementation end-to-end (dual-token path, context precedence, three role systems, SSO bridges, honest gaps, the May 2026 incident), scored self-review, status tracking, module depth, tradeoffs ledger, roadmap, meta-lessons |
| UX design | [user-experience.md](Work-Skills/Programming-Tech/Software%20Development/user-experience.md) | **A 13-check UX review list** for multi-role products (roles, reach, land, feedback, empty states, scale, handoffs …) + 2 added checks; **case study** — Project Mentor track vs team surfaces: orthogonal role modelling, organise-by-job-not-role, group-don't-nest, route-don't-filter, tab-preserving switcher; 12 transferable principles |
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
