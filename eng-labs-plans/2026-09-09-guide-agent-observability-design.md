# Guide-Agent Observability — Phase 1 Design

**Date:** 2026-09-09
**Status:** Approved design, pending implementation plan
**Scope:** Observability layer only. Evaluation layer (evals, golden datasets, quality scoring) is explicitly deferred to a later phase.

## Goal

Make every guide-agent turn debuggable from GCP without SSH or guesswork. The primary requirement: for any turn, see the **exact combined input sent to the model** (system message + history + current message, and what each subsequent in-loop model call saw), the tool calls and results, the raw and final output, and token/cost numbers. For any session, see **all of its turns' traces chronologically** via a single filter.

## Decisions made

| Decision | Choice |
|----------|--------|
| Scope | End-to-end trace: API → Cloud Tasks → guide-agent → callback as one connected trace |
| Cost visibility | Per-turn (span attributes) + aggregate (metrics). No per-tenant cost breakdown yet |
| Content capture | Full prompt/completion capture **in Cloud Logging** (not spans, not DB). Spans carry metadata only |
| Instrumentation approach | Manual OTel with the standard Python SDK + FastAPI/httpx auto-instrumentation. No third-party LLM instrumentation library |
| Capture store | Cloud Logging structured entries, linked to traces by `trace_id`. 30-day default retention accepted for phase 1 |
| Session view | `session_id`/`turn_id`/`group_id`/`tenant_id` attributes on every span and log entry; saved Logs Explorer / Trace filters as the UI |

## Architecture

```
apps/api (already instrumented, Node/OTel)
  └─ guide-queue.ts enqueue ──► Cloud Tasks task
         + traceparent header          │ (headers forwarded verbatim)
                                       ▼
apps/guide-agent (NEW: OTel Python SDK)
  POST /turn  ← FastAPI auto-instr extracts traceparent, continues the trace
  ├─ REVIEW inbound          span + review log
  ├─ CALL gemini (loop)      span + gen_ai.* attrs + capture logs (below)
  │   ├─ TOOL <name>         one span + one log per tool execution
  │   └─ ...
  ├─ REVIEW outbound         span + review log
  └─ DELIVER callback        httpx auto-instr propagates trace into apps/api
```

- **SDK bootstrap** mirrors `packages/telemetry/src/instrumentation.ts` in Python: OTLP HTTP exporters to `telemetry.googleapis.com` authenticated via ADC; disabled when `OTEL_SDK_DISABLED=true` (same convention as the API). Service name `guide-agent`.
- **Logging**: stdlib `logging` with a JSON formatter that injects `trace_id`, `span_id`, and the `logging.googleapis.com/trace` fields from the active span — the Python mirror of `packages/telemetry/src/logger.ts`. Replaces bare `print` in request paths (module `__main__` smoke-test prints stay).
- **Local dev**: the Redis dev dispatcher (`apps/guide-agent/dev/dispatcher.py`) carries the `traceparent` value in its payload so local traces connect the same way Cloud Tasks does. `LOG_PRETTY`-equivalent human-readable logs for laptops.

## Span map (metadata only — no content on spans)

| Span | Attributes |
|------|-----------|
| `POST /turn` (root, auto) | `session_id`, `turn_id`, `group_id`, `tenant_id`, queue wait ms |
| `REVIEW inbound` | verdict, tokens in/out |
| `CALL gemini` | `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, cost USD, loop iteration count |
| `TOOL <tool name>` | tool name, duration, error flag |
| `REVIEW outbound` | verdict, rewrite/block reason category, tokens in/out |
| `DELIVER callback` (auto) | status code |

The four correlation attributes (`session_id`, `turn_id`, `group_id`, `tenant_id`) are set on **every** span.

## Turn capture logs (the core requirement)

Captured via a LangChain **callback handler** attached to the model, which fires on every model invocation inside the agent loop. All entries carry `turn_id`, `session_id`, `group_id`, `tenant_id`, `trace_id`. Each entry ≤ 256KB; oversized payloads split into ordered parts (`part`/`of` fields), never truncated.

| Log event | Content |
|-----------|---------|
| `guide.turn.model_input` | First model call: the complete combined message array **verbatim, in order** (system message incl. `to_markdown(ctx)` and directive, history, current message). Plus a hash of the static prompt blocks so the running prompt version is identifiable |
| `guide.turn.model_input_delta` | Each subsequent in-loop model call: only the newly appended messages (tool results), with the iteration number — call N's full input is reconstructable as input + deltas 1..N |
| `guide.turn.tool_call` | One per tool execution: name, arguments, result (passed through the existing `redact.py`) |
| `guide.turn.output` | Raw model text before outbound review, final text after review, tokens in/out, cost |
| `guide.turn.review` | Inbound and outbound reviewer verdicts and reasons |

**Session debugging workflow this enables:** filter logs or traces on `session_id` → every turn of the session in chronological order → click any turn's trace → read its capture logs in timeline order.

## Metrics (low-cardinality attributes only)

- `guide.turn.duration` (histogram, s)
- `guide.turn.tokens` (counter, attrs: direction=in|out)
- `guide.turn.cost` (counter, USD)
- `guide.review.rejection.count` (counter, attr: reason category — bounded enum)
- `guide.tool.error.count` (counter, attr: tool name — bounded set)
- `guide.queue.wait` (histogram, ms)

No user/session/tenant IDs on metrics (cardinality rule); those live on spans and logs.

## Cost computation

Cost USD computed from token counts × a price table for the configured model, kept in one Python module with the model name as key. When the model isn't in the table, cost is omitted (never guessed) and a warning is logged once.

## Delivery — trunk-based

Four short-lived branches off `main`, each a small independently-green PR:

1. **PR 1 — bootstrap:** OTel SDK init + JSON logging with trace injection in guide-agent; `OTEL_SDK_DISABLED` honored; no behavior change.
2. **PR 2 — turn instrumentation:** spans per pipeline step, callback-handler capture logs, GenAI/cost attributes, correlation attributes.
3. **PR 3 — propagation:** `traceparent` injection in `guide-queue.ts`, extraction in FastAPI, dev dispatcher payload support.
4. **PR 4 — metrics + docs:** the six instruments + a README section: "how to read a turn / a session in GCP".

Each PR passes `/evaluate` and `bash scripts/pre-push.sh` before commit. Abhinav pushes and opens PRs himself. No feature flag beyond `OTEL_SDK_DISABLED` — observability is non-behavioral; the kill switch covers rollback.

## Testing

- Capture splitting at the 256KB boundary (part/of ordering, no data loss)
- Redaction applied to tool-call results before logging
- Cost math per model, unknown-model fallback
- Trace-context round-trip through the dev dispatcher (traceparent in → same trace_id out)
- Callback handler fires per loop iteration; delta contains only new messages
- Log formatter injects trace fields when a span is active, omits cleanly when not
- apps/api side: guide-queue.ts header injection unit test (Node/Jest, existing conventions)

## Out of scope (phase 1)

- Evaluation layer: evals, LLM-as-judge, golden datasets, quality scoring
- Durable capture storage (DB/GCS) and retention beyond Cloud Logging defaults
- Per-tenant cost attribution
- GCP dashboards and alert policies (metrics land; dashboards are a follow-up)
- Custom session-browser UI in the dashboard app
