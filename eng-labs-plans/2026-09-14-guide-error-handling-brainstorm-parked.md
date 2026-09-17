# PARKED BRAINSTORM — Guide pipeline error-handling overhaul

Status: mid-brainstorm (superpowers:brainstorming), parked 2026-09-14 before design presentation.
Resume point: **present Approach A's design section-by-section → user approval → write spec to docs/superpowers/specs/ → writing-plans skill.**
Approach A is recommended and pending explicit user approval (user asked to park instead of answering).

## The initiative (user's words, distilled)

Exception/error handling across the system is poor: generic "something went wrong" reaches the frontend, status codes are wrong, catch blocks log badly or not at all. Overhaul it — using the observability plumbing (4-PR stack, merged to main 2026-09-12) to carry proper custom logs/traces/metrics at the important places.

## Decisions already made (answered via AskUserQuestion)

1. **First slice = guide pipeline** (apps/guide-agent + its apps/api routes + guide UI). Platform-wide is a program, not a project; this slice is the template. Later slices: apps/api platform-wide, then frontend messaging layer.
2. **Student disclosure = category + action + reference ID.** Human-readable failure category, what-to-do guidance, and a support reference. No internals/stack traces to students. Full detail goes to logs only.
3. **Scope = messaging + fast failure.** Not just better messages for existing behavior: also a terminal-failure callback so a dead turn reaches the student in seconds instead of after the 10-minute watchdog (`TURN_EXPIRED`).

Derived decisions (stated, unobjected):
- Reference ID = `turn_id` (already on every message, already correlates all logs/traces — no new machinery).
- Categories = error-code enum extending the existing `ERROR_CODES` pattern in `@repo/helpers`, shared vocabulary across Python/TS/UI/logs.

## Approach A (recommended, pending approval)

Typed error envelope end-to-end:

- **guide-agent**: `GuideError` exception class carrying `{category, retryable, student_action}`. ~7 bounded categories: `MODEL_UNAVAILABLE`, `MODEL_EMPTY_RESPONSE`, `CONTEXT_INVALID`, `TOOL_UNAVAILABLE`, `ATTACHMENT_UNREADABLE`, `BUDGET_EXHAUSTED`, `INTERNAL`. Failure sites raise/wrap.
- **main.py classification**: retryable → 503 as today (Cloud Tasks retries). Terminal category OR final retry attempt → call new internal callback. Key trick: agent already reads `X-CloudTasks-TaskRetryCount` (added in PR 4's queue-wait fix) → "last retry" is detectable → convert retryable to terminal on final attempt.
- **apps/api**: new internal endpoint `POST /internal/guide-turns/:id/fail` beside existing `/complete` (see `completeTurn` in project-guide.service.ts — idempotency pattern to copy). Marks message/job row FAILED + `error_code` (small migration: error_code column). Watchdog stays as backstop.
- **dashboard**: `use-guide.ts` polling already reads message state — add FAILED state; one copy map (code → human message + action) in the guide UI; render category + action + turn_id reference.
- **logging**: structured `guide.turn.failure` event (category, turn_id, correlation ids) on every failure path; FIX the silent `_refuse` paths in `artifacts.py`/`attachments.py` (known gap: they return refusals to the model, log nothing — found during obs project, deferred).
- **metrics**: optional failure counter by category (bounded enum — fits telemetry.py pattern).

Rejected: B (infer categories by parsing existing 503 detail strings — brittle, loses fast-fail), C (platform-wide framework first — too big, contradicts slice decision).

## Context pointers (verified during obs project)

- Watchdog/TURN_EXPIRED semantics: `apps/api/src/routes/internal/guide-turn-watchdog.ts`, TURN_DEADLINE_MS in project-guide.service.ts, agent 503 contract in `apps/guide-agent/main.py` (~line 204 except block).
- Existing conventions: `responseWrapper`, `ERROR_CODES` (@repo/helpers), telemetry rule "silent catch prohibited", `.claude/review-rules/`.
- Known failure surfaces mapped: model-returned-no-text (agent.py raise), tool `_refuse` silent paths (artifacts.py:788-798, attachments.py:294/501), delivery-callback failures (main.py `_deliver`), context 400s.
- Observability rollout memory: `guide-agent-observability-rollout.md` (memory dir) — incl. open infra gap (GCP_PROJECT_ID + IAM) that gates traces/metrics in prod.
- Process to follow: brainstorm → spec (docs/superpowers/specs/) → writing-plans → subagent-driven-development, PRs under the 1000-line size gate, stacked if needed, /evaluate + pre-push.sh before commits, user pushes.

## Also pending from the observability close-out (separate from this initiative)

1. Infra ticket: GCP_PROJECT_ID env + roles/cloudtrace.agent, roles/monitoring.metricWriter, roles/logging.logWriter for guide-agent SA (and api SA) — without it prod telemetry stays dormant.
2. PR 4 (feat/guide-obs-4-metrics): user still to `git push --force-with-lease` → review → squash-merge. (Branch clean at 6f735c4c locally.)
3. Post-deploy smoke: same trace_id in api enqueue log + agent /turn log for one real turn.
4. Durgesh sync: unify guide.turn.cost (agent tokens) with his guide.turn.usage (all calls) before cost dashboards.

## Real-world evidence captured 2026-09-14 (turn PeFe2xzxr5qNgWF2tYMWV, dev)

First real investigation using the observability stack. Findings that feed this initiative:
1. **Refusal-substitute messages can lie about withheld content.** Outbound reviewer refused a turn (model wrote a complete Milestones 2-4 script — correctly caught); its substitute text told the student "I've provided some tutorial links" but the links were inside the withheld raw answer. Student was promised content they never received. → add "refusal message honesty" to the messaging scope.
2. **The 10-minute-watchdog pain is visible in a real thread**: the same student asked the same milestone question 5+ times over hours, receiving "No agent is connected" and TURN_EXPIRED fallbacks — the exact UX the fast-fail callback fixes.
3. Incidental: model violated NO_TASK_PROMPTS (wrote the full script anyway); the outbound reviewer backstop worked this time (it's LLM-based and fails open — see guiding-agent-trouble-spots #1).
4. **Hallucinated externals, verified 2026-09-14**: the withheld answer's HF dataset IDs (`darpa-cyber-security/nsl-kdd`, `rt-iot-2022/rt-iot-2022`) don't exist (HF API 401/not-found), and 2 of 4 cited doc URLs are 404 (shap example notebook, mealpy GWO). Zero web_search/web_fetch calls that turn — every external came from model memory. Root gap: grounding (extract_outbound/TRACEABLE) traces NUMBERS only; URLs and dataset/package identifiers are never checked. Full turn record: scratchpad/turn-report.md (session) — re-derivable from Cloud Logging turn_id PeFe2xzxr5qNgWF2tYMWV.
5. **Prod exhibit (turn _gkrZc0PFQaX7tLi-ywz0, 2026-09-15, trace c535a9aa…, report in ~/My Learnings/eng-labs-plans/):** guide correctly verified milestones 2-4 (23 iterations, 15 tool calls, $0.30, 561k tokens in), ALREADY updated milestones (VERIFIED on positions 300/400 + evidence + journal entry) — then outbound reviewer withheld the excellent answer (image-screenshot-derived counts 11,455/26,337 not in the traceable-numbers set → G4 refusal). Student saw "I cannot confirm…" while the DB says VERIFIED. Two new findings: (a) numbers read from IMAGE attachments never enter answer.read_text → untraceable by construction; (b) tool side effects commit before the outbound review, so a substituted refusal can deny actions already taken — substitute messages must acknowledge committed actions, or the revise-loop fix makes this moot.
