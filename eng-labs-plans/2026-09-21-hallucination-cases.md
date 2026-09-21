# Hallucination cases in the guiding agent — what we have actually observed

_Everything on record as of 2026-09-21, from two fully investigated turns plus the milestone audit. Sources: turn reports in this folder, the parked error-handling brainstorm, and `agentic-systems.md` §9. Each case carries its tag from the §9.1 vocabulary; the one-line cause for every one is collected at the end._

## Case 1 — fabricated externals (dev, turn `PeFe2xzxr5qNgWF2tYMWV`, 2026-09-14)

A student asked for help with their pipeline. The model wrote a complete script and cited external resources — all of it from memory.

- **H1 · invented dataset identifiers** — `darpa-cyber-security/nsl-kdd` and `rt-iot-2022/rt-iot-2022`. Both verified nonexistent (HuggingFace API returned 401 / not-found). Both are perfectly well-formed HF paths, which is why nothing about them looked wrong.
- **H2 · dead URLs** — 2 of 4 cited documentation links 404'd (a SHAP example notebook, a mealpy GWO page).
- **H3 · the refusal message promised withheld content** — the outbound reviewer held the turn (correctly: the answer was a complete script, violating `NO_TASK_PROMPTS`). Its substitute told the student *"I've provided some tutorial links"*. The links were inside the answer that was withheld. The student was promised content they never received.

**Zero `web_search` / `web_fetch` calls on that turn.** Every external came from model memory, and the reviewer refused the turn for the *code*, never noticing the fabrications at all.

Tags: `hallucinated-source` (H1, H2), `unusable` (H3).

## Case 2 — a false claim about its own actions (prod, turn `_gkrZc0PFQaX7tLi-ywz0`, 2026-09-15, trace `c535a9aa…`)

23 iterations, 15 tool calls, 561k input tokens, $0.30. The answer was substantially correct.

- **H4 · claimed an action that was refused** — the answer said *"Milestone 1: I've marked this as verified."* The corroboration guardrail had **refused** that write; only milestones 2, 3 and 4 applied. The same answer contradicted itself three lines later (*"I'll update the remaining milestone statuses (1 and 5) in our next check-in"*), and nothing caught either half.
- **H5 · the inverse — correct numbers refused as invented** — 11,455 and 26,337 were read off the student's own uploaded screenshot. An image contributes no text to `read_text`, so both arrived at the reviewer stamped "not accounted for", indistinguishable from fabrications. The whole turn was discarded.
- **H6 · the substitute denied work already done** — the student was told *"I cannot confirm the exact number of images processed until you share the actual output"*. They had already shared it, and the milestones had already moved in the database.

Tags: `hallucinated-source` (H4), `wrong-refusal` (H5), `unusable` (H6).

## Case 3 — relevance asserted, never checked (milestone audit, 2026-09-18)

- **H7 · one result verifying several milestones** — four milestones show as passed, each citing a `result` item describing the same preprocessing logs, written up in four different sentences. The corroboration check tests that a cited result is *verified*; it never tests that it is *about* that milestone, and no verification record says which milestone it covered.

Tag: `hallucinated-source`.

## The classes, and whether anything guards them

| Class | Observed | Guarded today |
|:--|:--|:--|
| Numbers about the team's results | H5 (as a false positive) | yes — traceable set; blind to images |
| External identifiers (datasets, packages, models) | H1 | **no** |
| URLs and links | H2 | **no** — though `blocks._is_cited` already computes the signal and discards it |
| Paper citations (doi, arXiv, title) | not yet | partially — `_is_cited` exists for rendering |
| Claims about actions taken | H4 | **no** — fixed on the evidence branch |
| Relevance of cited evidence | H7 | **no** |
| Repo paths or files never opened | not yet | **no** |
| Fidelity of quotes ("your config sets seed=42") | not yet | provenance only, never content |
| General world knowledge | not yet | **no** — and not checkable locally |

## Why each one happened — one line each

- **H1 — invented dataset identifiers:** nothing traces identifiers, so an external asserted from memory is indistinguishable from one that was fetched.
- **H2 — dead URLs:** the grounding check covers numbers only; a link to something the turn never opened is detected in `blocks.py` and silently discarded instead of flagged.
- **H3 — refusal promised withheld content:** the refusal sentence is written by a reviewer that never checks its own claim against the answer it is suppressing.
- **H4 — claimed a refused action as done:** the outbound reviewer is never told what the turn's tools actually did, so a claim about an action has nothing to be checked against.
- **H5 — correct numbers refused:** an image contributes no text to `read_text`, so a number read with eyes can never enter the traceable set, and "untraced" is treated as "invented".
- **H6 — substitute denied work already done:** tool side effects commit mid-loop before any reviewer decides, and a withheld turn rolls back artifacts only — never milestone moves or verifications.
- **H7 — one result verifying several milestones:** the corroboration check asks whether a cited result is verified, never whether it is relevant, and `guide_verifications` has no milestone column to record what the verdict was actually about.

## The common cause underneath

Six of the seven are the same shape: **the system can check provenance but never checks it for anything except numbers, and the one component that could judge the rest is handed no facts about what the turn did.** H5 is the same gap seen from the other side — provenance that exists but cannot be recorded, treated as provenance that does not exist.

## Status

`fix/outbound-reviewer-evidence` (rebased on main, 408 tests green, unpushed) addresses H4 and H5, and makes H6 visible for the first time. H1, H2 and H7 are unaddressed; the link tracer for H2 is the cheapest next one, because the detection already exists and only needs reporting. The benchmark table in `agentic-systems.md` §9.3 is still empty — these seven are its first rows.
