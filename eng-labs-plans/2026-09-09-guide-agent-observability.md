# Guide-Agent Observability (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** End-to-end OTel observability for the guide-agent: connected traces API→queue→agent→callback, full turn-content capture in Cloud Logging (exact model inputs per call), token/cost accounting, and session-level correlation — per spec `docs/superpowers/specs/2026-09-09-guide-agent-observability-design.md`.

**Architecture:** A new flat-module telemetry layer inside `apps/guide-agent` (`jsonlog.py`, `telemetry.py`, `costs.py`, `capture.py`) mirroring `packages/telemetry`'s conventions in Python; span wrapping in `turn.py`/`agent.py`; a LangChain callback handler for verbatim input capture; `traceparent` + `enqueuedAt` injected at the enqueue seam in `apps/api/src/helpers/guide-queue.ts` and forwarded by the dev dispatcher.

**Tech Stack:** opentelemetry-sdk (Python), OTLP HTTP exporters to `telemetry.googleapis.com` with google-auth ADC tokens, FastAPI/httpx auto-instrumentation, stdlib `logging` with a JSON formatter, `@opentelemetry/api` (already a dep) on the Node side.

## Global Constraints

- **Before every commit:** run `/evaluate` on changed files, then `bash scripts/pre-push.sh` and confirm green (start CockroachDB first: `docker compose -f packages/database/docker-compose.yml up -d`). This is CLAUDE.md's hard rule — no exceptions, including doc-only commits.
- **Never push.** Abhinav pushes branches and opens PRs himself (two-repo-setup rule).
- **Trunk-based:** each PR section below is its own short-lived branch off `main`: `feat/guide-obs-1-bootstrap`, `feat/guide-obs-2-turn`, `feat/guide-obs-3-propagation`, `feat/guide-obs-4-metrics`.
- **No content on spans.** Prompt/completion text goes only to Cloud Logging capture events. Span attributes are metadata (ids, counts, verdict categories).
- **Metric attributes must be bounded enums** — never ids or free text (repo telemetry rule 3).
- **Correlation fields** on every capture log event and every custom span: `turn_id`, `session_id`, `group_id`, `tenant_id` (spans additionally get them via `_set_correlation`).
- **Kill switch:** `OTEL_SDK_DISABLED=true` must leave the service behaving exactly as today (the `opentelemetry-api` no-op path makes span/metric calls safe; capture logging is gated separately by `GUIDE_CAPTURE_DISABLED=true`).
- **Python style:** flat modules, module docstrings explaining *why*, stdlib logging via module-level `log = logging.getLogger("guide-agent.<mod>")`. Tests live in `apps/guide-agent/tests/`, run with `python -m pytest` from `apps/guide-agent/` (conftest puts the app dir on `sys.path`).
- **guide-agent has no coverage gate** — its CI is `.github/workflows/guide-agent-test.yml` (pip install requirements + pytest). The API's 90% threshold applies only to the `apps/api` change in PR 3.

---

## PR 1 — branch `feat/guide-obs-1-bootstrap`

### Task 1: JSON logging with trace correlation (`jsonlog.py`)

**Files:**
- Create: `apps/guide-agent/jsonlog.py`
- Test: `apps/guide-agent/tests/test_jsonlog.py`
- Modify: `apps/guide-agent/requirements.txt` (add OTel deps — needed by this module's imports)
- Also commit: `docs/superpowers/specs/2026-09-09-guide-agent-observability-design.md` and this plan (they ride with the first commit)

**Interfaces:**
- Consumes: nothing internal; `opentelemetry.trace` API.
- Produces: `configure_logging() -> None` (installs root JSON handler; honors `LOG_LEVEL`, `LOG_PRETTY=true` for human-readable local output); `log_event(logger: logging.Logger, event: str, **fields) -> None` (structured event line — Task 4/6 call this); `JsonFormatter` (exported for tests).

- [ ] **Step 1: Add dependencies to `apps/guide-agent/requirements.txt`** (append, with a comment matching the file's commented style):

```
# Observability — OTel SDK + OTLP HTTP exporters to telemetry.googleapis.com,
# authenticated with ADC via google-auth (already transitive through
# langchain-google-genai, pinned here because telemetry.py imports it directly).
# See docs/superpowers/specs/2026-09-09-guide-agent-observability-design.md.
opentelemetry-sdk>=1.27
opentelemetry-exporter-otlp-proto-http>=1.27
opentelemetry-instrumentation-fastapi>=0.48b0
opentelemetry-instrumentation-httpx>=0.48b0
google-auth>=2.30
```

Then install into the venv: `cd apps/guide-agent && .venv/bin/pip install -r requirements.txt` (or `pip install -r requirements.txt` if no venv — match how the existing tests run).

- [ ] **Step 2: Write the failing test** — `apps/guide-agent/tests/test_jsonlog.py`:

```python
"""JsonFormatter: single-line JSON, GCP severity, trace correlation, fields merge."""

import json
import logging

from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

from jsonlog import JsonFormatter, log_event

# One provider for the whole test process — set_tracer_provider only works once.
_provider = TracerProvider()
_provider.add_span_processor(SimpleSpanProcessor(InMemorySpanExporter()))
trace.set_tracer_provider(_provider)


def _format(record_factory):
    record = record_factory()
    return json.loads(JsonFormatter().format(record))


def _record(level=logging.INFO, msg="hello", fields=None):
    def make():
        r = logging.LogRecord("guide-agent.test", level, __file__, 1, msg, None, None)
        if fields is not None:
            r.fields = fields
        return r
    return make


def test_plain_record_is_json_with_severity():
    out = _format(_record(level=logging.WARNING))
    assert out["message"] == "hello"
    assert out["severity"] == "WARNING"
    assert out["logger"] == "guide-agent.test"


def test_error_maps_to_error_severity():
    assert _format(_record(level=logging.ERROR))["severity"] == "ERROR"


def test_fields_are_merged_flat():
    out = _format(_record(fields={"turn_id": "m1", "tokens_in": 12}))
    assert out["turn_id"] == "m1"
    assert out["tokens_in"] == 12


def test_no_active_span_means_no_trace_fields():
    out = _format(_record())
    assert "trace_id" not in out


def test_active_span_injects_trace_ids(monkeypatch):
    monkeypatch.setenv("GCP_PROJECT_ID", "proj-x")
    tracer = trace.get_tracer("test")
    with tracer.start_as_current_span("t") as span:
        out = _format(_record())
        ctx = span.get_span_context()
    assert out["trace_id"] == format(ctx.trace_id, "032x")
    assert out["span_id"] == format(ctx.span_id, "016x")
    assert out["logging.googleapis.com/trace"] == f"projects/proj-x/traces/{format(ctx.trace_id, '032x')}"


def test_log_event_emits_fields(caplog):
    log = logging.getLogger("guide-agent.capture-test")
    with caplog.at_level(logging.INFO, logger="guide-agent.capture-test"):
        log_event(log, "guide.turn.output", turn_id="m1", tokens_in=5)
    record = caplog.records[-1]
    assert record.getMessage() == "guide.turn.output"
    assert record.fields == {"event": "guide.turn.output", "turn_id": "m1", "tokens_in": 5}
```

- [ ] **Step 3: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_jsonlog.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'jsonlog'`

- [ ] **Step 4: Implement `apps/guide-agent/jsonlog.py`:**

```python
"""Structured JSON logging with OTel trace correlation.

The Python twin of packages/telemetry/src/logger.ts: every record formatted
here carries the active span's trace_id/span_id plus the
logging.googleapis.com/* fields Cloud Logging uses to link a log line to its
Cloud Trace span. Output is single-line JSON because Cloud Run ships stdout to
Cloud Logging as-is; LOG_PRETTY=true keeps laptop output human-readable, same
convention as the Node side. Works with a no-op tracer too — when
OTEL_SDK_DISABLED skips SDK setup, get_current_span() returns an invalid
context and the trace fields are simply omitted.
"""

from __future__ import annotations

import json
import logging
import os

from opentelemetry import trace

_GCP_SEVERITY = {
    "DEBUG": "DEBUG",
    "INFO": "INFO",
    "WARNING": "WARNING",
    "ERROR": "ERROR",
    "CRITICAL": "CRITICAL",
}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry: dict = {
            "message": record.getMessage(),
            "severity": _GCP_SEVERITY.get(record.levelname, "DEFAULT"),
            "logger": record.name,
        }
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)

        fields = getattr(record, "fields", None)
        if isinstance(fields, dict):
            entry.update(fields)

        ctx = trace.get_current_span().get_span_context()
        if ctx.is_valid:
            trace_id = format(ctx.trace_id, "032x")
            span_id = format(ctx.span_id, "016x")
            entry["trace_id"] = trace_id
            entry["span_id"] = span_id
            project = os.environ.get("GCP_PROJECT_ID")
            if project:
                entry["logging.googleapis.com/trace"] = f"projects/{project}/traces/{trace_id}"
                entry["logging.googleapis.com/spanId"] = span_id
                entry["logging.googleapis.com/traceSampled"] = bool(ctx.trace_flags & 1)

        return json.dumps(entry, default=str)


def log_event(logger: logging.Logger, event: str, **fields) -> None:
    """One structured event line. `event` doubles as the message so Logs
    Explorer's summary column reads without expanding the entry."""
    logger.info(event, extra={"fields": {"event": event, **fields}})


def configure_logging() -> None:
    """Install the JSON handler on the root logger. Replaces main.py's
    logging.basicConfig — call once, before the app handles anything."""
    root = logging.getLogger()
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())
    handler = logging.StreamHandler()
    if os.environ.get("LOG_PRETTY") != "true":
        handler.setFormatter(JsonFormatter())
    root.handlers[:] = [handler]
```

- [ ] **Step 5: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest tests/test_jsonlog.py -v`
Expected: all PASS

- [ ] **Step 6: Full guide-agent suite still green**

Run: `cd apps/guide-agent && python -m pytest`
Expected: PASS (no regressions)

- [ ] **Step 7: Gates, then commit**

Run `/evaluate`, then `bash scripts/pre-push.sh`. When green:

```bash
git checkout -b feat/guide-obs-1-bootstrap
git add apps/guide-agent/jsonlog.py apps/guide-agent/tests/test_jsonlog.py \
  apps/guide-agent/requirements.txt \
  docs/superpowers/specs/2026-09-09-guide-agent-observability-design.md \
  docs/superpowers/plans/2026-09-09-guide-agent-observability.md
git commit -m "feat(guide-agent): structured JSON logging with trace correlation"
```

### Task 2: OTel SDK bootstrap + `with_span` (`telemetry.py`) and main.py wiring

**Files:**
- Create: `apps/guide-agent/telemetry.py`
- Test: `apps/guide-agent/tests/test_telemetry.py`
- Modify: `apps/guide-agent/main.py:58` (replace `logging.basicConfig`) and after `app = FastAPI(...)`

**Interfaces:**
- Consumes: `jsonlog.configure_logging` (called by main.py alongside this).
- Produces: `setup_telemetry(app) -> bool` (idempotent init; False when disabled/no creds); `with_span(name: str, attributes: dict | None = None)` context manager yielding the span — Tasks 5/6 use it; `_set_correlation(span, *, turn_id, session_id, group_id, tenant_id)` helper.

- [ ] **Step 1: Write the failing test** — `apps/guide-agent/tests/test_telemetry.py`:

```python
"""setup_telemetry kill switch + with_span error semantics.

No exporter reaches the network here: the disabled path returns before any
provider is built, and with_span is exercised against the in-memory provider
installed by test_jsonlog (shared process-wide provider)."""

import pytest
from opentelemetry import trace
from opentelemetry.trace import StatusCode

from telemetry import setup_telemetry, with_span


def test_disabled_env_skips_setup(monkeypatch):
    monkeypatch.setenv("OTEL_SDK_DISABLED", "true")
    assert setup_telemetry(app=None) is False


def test_with_span_yields_and_ends_ok():
    with with_span("TEST operation", {"k": "v"}) as span:
        assert span is not None
    # No exception escaped; nothing to assert beyond clean exit — status
    # inspection needs a real span, covered below when the SDK provider exists.


def test_with_span_records_error_and_reraises():
    class Boom(RuntimeError):
        pass

    with pytest.raises(Boom):
        with with_span("TEST failing"):
            raise Boom("x")


def test_with_span_sets_status_on_real_spans():
    # The process provider is the in-memory one from test_jsonlog's import.
    tracer_provider = trace.get_tracer_provider()
    if not hasattr(tracer_provider, "add_span_processor"):
        pytest.skip("no SDK provider installed in this process")
    with with_span("TEST ok") as span:
        pass
    assert span.status.status_code is StatusCode.OK
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_telemetry.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'telemetry'`

- [ ] **Step 3: Implement `apps/guide-agent/telemetry.py`:**

```python
"""OTel SDK bootstrap for the guide-agent, plus the with_span helper.

The Python twin of packages/telemetry/src/instrumentation.ts + tracer.ts:
OTLP HTTP straight to telemetry.googleapis.com (no Collector), authenticated
by refreshing an ADC token before each export batch. OTEL_SDK_DISABLED=true
skips everything — the opentelemetry-api no-op implementations make every
span/metric call in the codebase safe without the SDK.

Local dev without GCP credentials also degrades to disabled (with one log
line) rather than crashing the service: telemetry must never be the reason a
turn fails. Point OTEL_EXPORTER_OTLP_ENDPOINT at a local collector to develop
against real exports without ADC — auth headers are only attached for the
Google endpoint.
"""

from __future__ import annotations

import logging
import os
from contextlib import contextmanager

from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode

log = logging.getLogger("guide-agent.telemetry")

_GOOGLE_ENDPOINT = "https://telemetry.googleapis.com"
_initialised = False


def _tracer():
    return trace.get_tracer(os.environ.get("OTEL_SERVICE_NAME", "guide-agent"))


@contextmanager
def with_span(name: str, attributes: dict | None = None):
    """Run the body inside a new active span. Mirrors tracer.ts withSpan:
    end() always runs, an exception is recorded and re-raised, and nesting
    produces parent-child spans. Span names follow `VERB resource`."""
    with _tracer().start_as_current_span(name, attributes=attributes or {}) as span:
        try:
            yield span
            span.set_status(Status(StatusCode.OK))
        except Exception as e:
            span.record_exception(e)
            span.set_status(Status(StatusCode.ERROR, str(e)))
            raise


def _set_correlation(span, *, turn_id: str, session_id: str | None, group_id: str, tenant_id: str) -> None:
    span.set_attribute("turn_id", turn_id)
    span.set_attribute("session_id", session_id or "")
    span.set_attribute("group_id", group_id)
    span.set_attribute("tenant_id", tenant_id)


def setup_telemetry(app) -> bool:
    """Build providers, wire GCP-authenticated exporters, instrument FastAPI
    and httpx. Returns False (and changes nothing) when disabled or when no
    credentials resolve. Idempotent — uvicorn reloads must not double-register."""
    global _initialised
    if _initialised:
        return True
    if os.environ.get("OTEL_SDK_DISABLED", "").lower() == "true":
        log.info("OTEL_SDK_DISABLED=true — telemetry off")
        return False

    endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", _GOOGLE_ENDPOINT)
    needs_auth = endpoint.rstrip("/") == _GOOGLE_ENDPOINT

    credentials = None
    if needs_auth:
        try:
            import google.auth

            credentials, _ = google.auth.default(
                scopes=["https://www.googleapis.com/auth/cloud-platform"]
            )
        except Exception as e:  # DefaultCredentialsError and friends
            log.warning("telemetry disabled — no GCP credentials: %s", e)
            return False

    from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
    from opentelemetry.sdk.metrics import MeterProvider
    from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry import metrics as otel_metrics

    def _auth_headers() -> dict:
        if credentials is None:
            return {}
        import google.auth.transport.requests

        if not credentials.valid:
            credentials.refresh(google.auth.transport.requests.Request())
        return {"Authorization": f"Bearer {credentials.token}"}

    class _AuthedSpanExporter(OTLPSpanExporter):
        def export(self, spans):
            self._session.headers.update(_auth_headers())
            return super().export(spans)

    class _AuthedMetricExporter(OTLPMetricExporter):
        def export(self, metrics_data, timeout_millis: float = 10_000, **kwargs):
            self._session.headers.update(_auth_headers())
            return super().export(metrics_data, timeout_millis=timeout_millis, **kwargs)

    resource = Resource.create(
        {
            "service.name": os.environ.get("OTEL_SERVICE_NAME", "guide-agent"),
            "service.version": os.environ.get("OTEL_SERVICE_VERSION", "0.0.0"),
        }
    )

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(
        BatchSpanProcessor(_AuthedSpanExporter(endpoint=f"{endpoint}/v1/traces"))
    )
    trace.set_tracer_provider(tracer_provider)

    meter_provider = MeterProvider(
        resource=resource,
        metric_readers=[
            PeriodicExportingMetricReader(_AuthedMetricExporter(endpoint=f"{endpoint}/v1/metrics"))
        ],
    )
    otel_metrics.set_meter_provider(meter_provider)

    if app is not None:
        # Health probes are noise — same suppression the Node middleware applies.
        FastAPIInstrumentor.instrument_app(app, excluded_urls="health")
    HTTPXClientInstrumentor().instrument()

    _initialised = True
    log.info("telemetry initialised — exporting to %s", endpoint)
    return True
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest tests/test_telemetry.py tests/test_jsonlog.py -v`
Expected: all PASS (the `sets_status` test may skip if run standalone — fine)

- [ ] **Step 5: Wire main.py.** In `apps/guide-agent/main.py`, replace line 58 `logging.basicConfig(level=logging.INFO)` and add setup after `app = FastAPI(...)`:

```python
from jsonlog import configure_logging
from telemetry import setup_telemetry

configure_logging()

app = FastAPI(title="guide-agent")
log = logging.getLogger("guide-agent")

setup_telemetry(app)
```

(Keep the existing `import logging` — `log = logging.getLogger(...)` still uses it. Delete only the `logging.basicConfig(level=logging.INFO)` line.)

- [ ] **Step 6: Smoke-check the service boots with telemetry disabled**

Run: `cd apps/guide-agent && OTEL_SDK_DISABLED=true python -c "import main; print('boot ok')"`
Expected: `boot ok` (plus the "telemetry off" log line)

- [ ] **Step 7: Full suite, gates, commit**

Run: `cd apps/guide-agent && python -m pytest` → PASS. Then `/evaluate` + `bash scripts/pre-push.sh` → green.

```bash
git add apps/guide-agent/telemetry.py apps/guide-agent/tests/test_telemetry.py apps/guide-agent/main.py
git commit -m "feat(guide-agent): OTel SDK bootstrap, with_span helper, FastAPI/httpx auto-instrumentation"
```

**PR 1 done — hand to Abhinav to push `feat/guide-obs-1-bootstrap` and open the PR.**

---

## PR 2 — branch `feat/guide-obs-2-turn` (branched from main after PR 1 merges, or stacked locally)

### Task 3: Cost table (`costs.py`)

**Files:**
- Create: `apps/guide-agent/costs.py`
- Test: `apps/guide-agent/tests/test_costs.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `cost_usd(model: str, tokens_in: int, tokens_out: int) -> float | None` — None (plus one warning per unknown model per process) when the model has no price entry. Task 5 calls it with `agent.MODEL`.

- [ ] **Step 1: Write the failing test** — `apps/guide-agent/tests/test_costs.py`:

```python
"""cost_usd: price math, unknown-model None, warn-once."""

import logging

import costs
from costs import cost_usd


def test_known_model_math():
    price = costs.PRICES_PER_MTOK_USD["google_genai:gemini-3-flash-preview"]
    expected = (1_000_000 * price["in"] + 500_000 * price["out"]) / 1_000_000
    assert cost_usd("google_genai:gemini-3-flash-preview", 1_000_000, 500_000) == expected


def test_zero_tokens_zero_cost():
    assert cost_usd("google_genai:gemini-3-flash-preview", 0, 0) == 0.0


def test_unknown_model_returns_none_and_warns_once(caplog):
    costs._warned.clear()
    with caplog.at_level(logging.WARNING):
        assert cost_usd("nobody:mystery-model", 10, 10) is None
        assert cost_usd("nobody:mystery-model", 10, 10) is None
    warnings = [r for r in caplog.records if "mystery-model" in r.getMessage()]
    assert len(warnings) == 1
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_costs.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'costs'`

- [ ] **Step 3: Implement `apps/guide-agent/costs.py`:**

```python
"""Token → USD conversion for the models this service actually calls.

Keyed by the same provider:model string GUIDE_MODEL uses, so the lookup is
`cost_usd(agent.MODEL, ...)` with no translation layer. An unknown model costs
None, never a guess — a wrong number in a cost dashboard is worse than a gap —
and warns once per process so a model swap that forgets this table is loud in
the logs without being loud on every turn.

PRICES ARE PER MILLION TOKENS, USD. Verify against
https://ai.google.dev/pricing when touching this table — Google reprices.
"""

from __future__ import annotations

import logging

log = logging.getLogger("guide-agent.costs")

# NOTE TO IMPLEMENTER: confirm these two rows against Google's current price
# page before merging, and correct them if they have moved. The shape stays.
PRICES_PER_MTOK_USD: dict[str, dict[str, float]] = {
    "google_genai:gemini-3-flash-preview": {"in": 0.30, "out": 2.50},
    "google_genai:gemini-3.5-flash-lite": {"in": 0.10, "out": 0.40},
}

_warned: set[str] = set()


def cost_usd(model: str, tokens_in: int, tokens_out: int) -> float | None:
    price = PRICES_PER_MTOK_USD.get(model)
    if price is None:
        if model not in _warned:
            _warned.add(model)
            log.warning("no price entry for model %s — cost omitted", model)
        return None
    return (tokens_in * price["in"] + tokens_out * price["out"]) / 1_000_000
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest tests/test_costs.py -v`
Expected: PASS

- [ ] **Step 5: Verify current Gemini prices** (web check or Google pricing page) and correct `PRICES_PER_MTOK_USD` values if needed; re-run the test (it reads the table, so it stays green through price edits).

- [ ] **Step 6: Gates, commit**

```bash
git checkout -b feat/guide-obs-2-turn
git add apps/guide-agent/costs.py apps/guide-agent/tests/test_costs.py
git commit -m "feat(guide-agent): token cost table with warn-once unknown-model fallback"
```

(Gates: `/evaluate` + `pre-push.sh` first, as always.)

### Task 4: Turn capture callback handler (`capture.py`)

**Files:**
- Create: `apps/guide-agent/capture.py`
- Test: `apps/guide-agent/tests/test_capture.py`

**Interfaces:**
- Consumes: `jsonlog.log_event`, `redact.redact` (`redact(text: str | None) -> Redacted` with `.text` and `.redactions`), `telemetry.with_span` is NOT used here (tool spans are created directly — callbacks span start/end boundaries).
- Produces: `class TurnCapture(BaseCallbackHandler)` constructed as `TurnCapture(turn_id=..., session_id=..., group_id=..., tenant_id=..., prompt_hash=...)`; emits log events `guide.turn.model_input`, `guide.turn.model_input_delta`, `guide.turn.tool_call`; creates `TOOL <name>` spans. Also `MAX_ENTRY_BYTES` and `split_for_logging(fields: dict) -> list[dict]` (exported for tests). Task 5 passes the instance into `agent.run`.

- [ ] **Step 1: Write the failing test** — `apps/guide-agent/tests/test_capture.py`:

```python
"""TurnCapture: verbatim first input, deltas after, 256KB splitting, redacted tools.

Everything asserts on caplog records' `.fields` — capture is logging, so the
tests read what would land in Cloud Logging."""

import logging
import uuid

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage

from capture import MAX_ENTRY_BYTES, TurnCapture, split_for_logging

IDS = dict(turn_id="m1", session_id="s1", group_id="g1", tenant_id="t1")


def _events(caplog, name):
    return [r.fields for r in caplog.records if getattr(r, "fields", {}).get("event") == name]


def _capture_with_log(caplog):
    caplog.set_level(logging.INFO, logger="guide-agent.capture")
    return TurnCapture(**IDS, prompt_hash="abc123")


def test_first_model_call_logs_full_input(caplog):
    cap = _capture_with_log(caplog)
    msgs = [SystemMessage("sys"), HumanMessage("hist"), HumanMessage("current")]
    cap.on_chat_model_start({}, [msgs], run_id=uuid.uuid4())
    (entry,) = _events(caplog, "guide.turn.model_input")
    assert entry["turn_id"] == "m1" and entry["prompt_hash"] == "abc123"
    assert [m["role"] for m in entry["messages"]] == ["system", "human", "human"]
    assert entry["messages"][0]["content"] == "sys"


def test_second_call_logs_only_delta(caplog):
    cap = _capture_with_log(caplog)
    first = [SystemMessage("sys"), HumanMessage("q")]
    cap.on_chat_model_start({}, [first], run_id=uuid.uuid4())
    grown = first + [AIMessage("calling tool"), ToolMessage("result", tool_call_id="tc1")]
    cap.on_chat_model_start({}, [grown], run_id=uuid.uuid4())
    (delta,) = _events(caplog, "guide.turn.model_input_delta")
    assert delta["iteration"] == 1
    assert [m["role"] for m in delta["messages"]] == ["ai", "tool"]


def test_tool_result_is_redacted(caplog):
    cap = _capture_with_log(caplog)
    rid = uuid.uuid4()
    cap.on_tool_start({"name": "read_file"}, "AWS_SECRET_ACCESS_KEY=AKIAIOSFODNN7EXAMPLEKEY", run_id=rid)
    cap.on_tool_end("password=hunter2hunter2", run_id=rid)
    (entry,) = _events(caplog, "guide.turn.tool_call")
    assert entry["tool"] == "read_file"
    assert "hunter2" not in entry["result"]


def test_tool_error_is_logged(caplog):
    cap = _capture_with_log(caplog)
    rid = uuid.uuid4()
    cap.on_tool_start({"name": "web_fetch"}, "http://x", run_id=rid)
    cap.on_tool_error(RuntimeError("boom"), run_id=rid)
    (entry,) = _events(caplog, "guide.turn.tool_call")
    assert entry["error"] == "RuntimeError: boom"


def test_split_for_logging_respects_cap():
    big = "x" * (MAX_ENTRY_BYTES * 2)
    parts = split_for_logging({"messages": [{"role": "system", "content": big}]})
    assert len(parts) >= 2
    assert all(p["of"] == len(parts) for p in parts)
    assert [p["part"] for p in parts] == list(range(1, len(parts) + 1))
    rebuilt = "".join(m["content"] for p in parts for m in p["messages"])
    assert rebuilt == big


def test_small_payload_is_single_part():
    parts = split_for_logging({"messages": [{"role": "human", "content": "hi"}]})
    assert len(parts) == 1 and "part" not in parts[0]
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_capture.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'capture'`

- [ ] **Step 3: Implement `apps/guide-agent/capture.py`:**

```python
"""What the model actually saw, turn by turn, as Cloud Logging entries.

A LangChain callback handler fires on every model call inside the agent loop
— which is the only honest vantage point: the loop grows the conversation
with tool results between calls, so "the input" is per-call, not per-turn.
The first call logs the complete message array verbatim
(guide.turn.model_input); each later call logs only the newly appended
messages (guide.turn.model_input_delta), so call N's input is reconstructable
as input + deltas 1..N without re-shipping the whole thread every iteration.

Tool executions get a span (timing/status — metadata only) and a
guide.turn.tool_call log entry carrying redacted args and result. redact() is
non-negotiable here: tool results include repo file contents, and this module
is exactly the "results dump" its docstring warns about.

Entries stay under Cloud Logging's 256KB cap by splitting the message list —
and, when one message alone exceeds the cap, its content string — into
ordered parts (part/of). Split, never truncate: a capture that silently drops
the end of a system prompt answers the wrong question.

GUIDE_CAPTURE_DISABLED=true turns all logging from this module off (spans
stay) — the content kill switch, separate from OTEL_SDK_DISABLED on purpose.
"""

from __future__ import annotations

import json
import logging
import os
import time

from langchain_core.callbacks import BaseCallbackHandler
from opentelemetry import trace

from jsonlog import log_event
from redact import redact

log = logging.getLogger("guide-agent.capture")

# Headroom under the 256KB LogEntry cap for the envelope (ids, trace fields,
# Cloud Logging's own metadata).
MAX_ENTRY_BYTES = 200_000


def _role(m) -> str:
    return getattr(m, "type", m.__class__.__name__)


def _serialise(m) -> dict:
    out = {"role": _role(m), "content": m.content if isinstance(m.content, str) else json.loads(json.dumps(m.content, default=str))}
    name = getattr(m, "name", None)
    if name:
        out["name"] = name
    tool_calls = getattr(m, "tool_calls", None)
    if tool_calls:
        out["tool_calls"] = json.loads(json.dumps(tool_calls, default=str))
    return out


def _size(fields: dict) -> int:
    return len(json.dumps(fields, default=str).encode())


def split_for_logging(fields: dict) -> list[dict]:
    """Split `fields` (which carries a "messages" list) into entries that each
    serialise under MAX_ENTRY_BYTES. A single oversized message is split by
    slicing its content string; everything else splits on message boundaries."""
    if _size(fields) <= MAX_ENTRY_BYTES:
        return [fields]

    base = {k: v for k, v in fields.items() if k != "messages"}
    overhead = _size(base) + 200  # envelope allowance per part
    budget = MAX_ENTRY_BYTES - overhead

    pieces: list[dict] = []
    for m in fields.get("messages", []):
        content = m.get("content")
        if isinstance(content, str) and _size(m) > budget:
            step = max(budget - _size({**m, "content": ""}), 1_000)
            for i in range(0, len(content), step):
                pieces.append({**m, "content": content[i : i + step]})
        else:
            pieces.append(m)

    parts: list[list[dict]] = [[]]
    used = 0
    for piece in pieces:
        piece_size = _size(piece)
        if parts[-1] and used + piece_size > budget:
            parts.append([])
            used = 0
        parts[-1].append(piece)
        used += piece_size

    total = len(parts)
    return [{**base, "messages": chunk, "part": i + 1, "of": total} for i, chunk in enumerate(parts)]


class TurnCapture(BaseCallbackHandler):
    def __init__(self, *, turn_id: str, session_id: str | None, group_id: str, tenant_id: str, prompt_hash: str):
        self.ids = {
            "turn_id": turn_id,
            "session_id": session_id or "",
            "group_id": group_id,
            "tenant_id": tenant_id,
        }
        self.prompt_hash = prompt_hash
        self.iteration = 0
        self._seen = 0
        self._tools: dict = {}  # run_id -> (span, started_at, name, args)
        self._enabled = os.environ.get("GUIDE_CAPTURE_DISABLED", "").lower() != "true"

    def _emit(self, event: str, fields: dict) -> None:
        if not self._enabled:
            return
        for part in split_for_logging({**self.ids, **fields}):
            log_event(log, event, **part)

    # ── model calls ──────────────────────────────────────────────────────────

    def on_chat_model_start(self, serialized, messages, **kwargs) -> None:
        batch = [_serialise(m) for m in messages[0]]
        if self.iteration == 0:
            self._emit("guide.turn.model_input", {"prompt_hash": self.prompt_hash, "messages": batch})
        else:
            self._emit(
                "guide.turn.model_input_delta",
                {"iteration": self.iteration, "messages": batch[self._seen :]},
            )
        self._seen = len(batch)
        self.iteration += 1

    # ── tools: span + redacted log ───────────────────────────────────────────

    def on_tool_start(self, serialized, input_str, *, run_id, **kwargs) -> None:
        name = (serialized or {}).get("name", "unknown")
        span = trace.get_tracer("guide-agent").start_span(f"TOOL {name}")
        span.set_attribute("tool", name)
        for k, v in self.ids.items():
            span.set_attribute(k, v)
        self._tools[run_id] = (span, time.monotonic(), name, redact(str(input_str)).text)

    def _finish_tool(self, run_id, *, result: str | None, error: str | None) -> None:
        span, started, name, args = self._tools.pop(run_id, (None, None, "unknown", ""))
        fields = {"tool": name, "args": args}
        if error is not None:
            fields["error"] = error
        if result is not None:
            fields["result"] = redact(result).text
        if started is not None:
            fields["duration_ms"] = round((time.monotonic() - started) * 1000)
        self._emit("guide.turn.tool_call", fields)
        if span is not None:
            span.set_attribute("error", error is not None)
            span.end()

    def on_tool_end(self, output, *, run_id, **kwargs) -> None:
        self._finish_tool(run_id, result=str(output), error=None)

    def on_tool_error(self, error: BaseException, *, run_id, **kwargs) -> None:
        self._finish_tool(run_id, result=None, error=f"{type(error).__name__}: {error}")
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest tests/test_capture.py -v`
Expected: PASS. If `test_tool_result_is_redacted` fails because `redact` didn't scrub the sample, adjust the test's secret to a shape `redact.py`'s `_PATTERNS` actually matches (read `redact.py:1-84`) — the assertion is that redact() is *applied*, so use a pattern it catches.

- [ ] **Step 5: Full suite, gates, commit**

```bash
git add apps/guide-agent/capture.py apps/guide-agent/tests/test_capture.py
git commit -m "feat(guide-agent): TurnCapture callback — verbatim model inputs, deltas, redacted tool calls"
```

### Task 5: Wire spans + capture through `turn.py` / `agent.py`

**Files:**
- Modify: `apps/guide-agent/agent.py` (add `PROMPT_HASH`, `capture` parameter, config on invoke)
- Modify: `apps/guide-agent/turn.py` (spans around pipeline steps, build TurnCapture, review/output events)
- Test: `apps/guide-agent/tests/test_turn_instrumentation.py`

**Interfaces:**
- Consumes: `telemetry.with_span`, `capture.TurnCapture`, `costs.cost_usd`, `jsonlog.log_event`, `agent.MODEL`.
- Produces: `agent.run(..., capture=None)` keyword; `agent.PROMPT_HASH: str`; log events `guide.turn.review` (fields: stage `inbound|outbound`, refused bool, reason) and `guide.turn.output` (fields: raw_text, final_text, refused_by, tokens_in, tokens_out, cost_usd, iterations).

- [ ] **Step 1: Write the failing test** — `apps/guide-agent/tests/test_turn_instrumentation.py`:

```python
"""turn.run emits review/output events and spans without a real model.

review_inbound/review_outbound and agent.run are monkeypatched — this tests
the instrumentation seams, not the pipeline logic (existing tests own that)."""

import json
import logging

import pytest

import agent as agent_mod
import turn as turn_mod
from context import DEFAULT_FIXTURE, load_context


class _Verdict:
    def __init__(self, refused, reason=""):
        self.refused = refused
        self.reason = reason


@pytest.fixture()
def ctx():
    doc = json.loads(DEFAULT_FIXTURE.read_text())["data"]
    doc["messages"] = [
        {"id": "m1", "role": "student", "at": "2026-06-01T09:00:00.000Z", "text": "hello"}
    ]
    return load_context(doc)


def _events(caplog, name):
    return [r.fields for r in caplog.records if getattr(r, "fields", {}).get("event") == name]


def test_passed_turn_emits_output_event(ctx, caplog, monkeypatch):
    caplog.set_level(logging.INFO)
    monkeypatch.setattr(turn_mod, "review_inbound", lambda *a, **k: _Verdict(False))
    monkeypatch.setattr(turn_mod, "review_outbound", lambda *a, **k: _Verdict(False))
    monkeypatch.setattr(
        turn_mod.agent, "run",
        lambda *a, **k: agent_mod.Answer("the answer", 100, 20),
    )
    monkeypatch.setattr(turn_mod.agent, "summarise", lambda *a, **k: "sum")

    out = turn_mod.run(ctx, [])

    assert out["refused_by"] is None
    (output,) = _events(caplog, "guide.turn.output")
    assert output["raw_text"] == "the answer"
    assert output["tokens_in"] == 100
    assert output["turn_id"] == "m1"
    reviews = _events(caplog, "guide.turn.review")
    assert [r["stage"] for r in reviews] == ["inbound", "outbound"]
    assert all(r["refused"] is False for r in reviews)


def test_inbound_refusal_emits_refused_review_and_output(ctx, caplog, monkeypatch):
    caplog.set_level(logging.INFO)
    monkeypatch.setattr(turn_mod, "review_inbound", lambda *a, **k: _Verdict(True, "injection"))

    out = turn_mod.run(ctx, [])

    assert out["refused_by"] == "inbound"
    (review,) = _events(caplog, "guide.turn.review")
    assert review == {**review, "stage": "inbound", "refused": True, "reason": "injection"}
    (output,) = _events(caplog, "guide.turn.output")
    assert output["refused_by"] == "inbound"


def test_agent_run_accepts_capture_kwarg(monkeypatch):
    # Signature contract: turn.py passes capture=...; a rename breaks here, not in prod.
    import inspect

    assert "capture" in inspect.signature(agent_mod.run).parameters


def test_prompt_hash_is_stable_hex():
    assert isinstance(agent_mod.PROMPT_HASH, str) and len(agent_mod.PROMPT_HASH) == 12
    int(agent_mod.PROMPT_HASH, 16)  # raises if not hex
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_turn_instrumentation.py -v`
Expected: FAIL — no `PROMPT_HASH`, no `capture` parameter, no events emitted.

- [ ] **Step 3: Modify `apps/guide-agent/agent.py`:**

3a. Add near the top (after existing imports): `import hashlib`.

3b. After the block where `CITE_SOURCES`, `NO_TASK_PROMPTS`, `ARTIFACTS` are all defined (search for the last of the three), add:

```python
# Version fingerprint of the static prompt blocks. Logged with every capture
# so a debugging session can tell which prompt text produced an answer —
# to_markdown(ctx) varies per turn, these three do not.
PROMPT_HASH = hashlib.sha256(
    f"{CITE_SOURCES}\n\n{NO_TASK_PROMPTS}\n\n{ARTIFACTS}".encode()
).hexdigest()[:12]
```

3c. Change `run()`'s signature — add a trailing keyword param:

```python
def run(
    ctx: GuideContext,
    tools: list[...unchanged...],
    message: str,
    at: str,
    attachments: list | None = None,
    capture=None,
) -> Answer:
```

3d. Change the invoke at `agent.py:351`:

```python
    result = agent.invoke(
        {"messages": [system, *history, HumanMessage(current)]},
        config={"callbacks": [capture]} if capture is not None else None,
    )
```

- [ ] **Step 4: Modify `apps/guide-agent/turn.py`:**

4a. Add imports after the existing ones:

```python
from capture import TurnCapture
from costs import cost_usd
from jsonlog import log_event
from telemetry import with_span
```

4b. Inside `run()`, after `history, message, at, attachments, message_id = _history_and_current(ctx)`, build the ids and capture:

```python
    ids = dict(
        turn_id=message_id,
        session_id=ctx.session_id or "",
        group_id=ctx.group_id,
        tenant_id=ctx.tenant_id,
    )
    capture = TurnCapture(
        turn_id=message_id,
        session_id=ctx.session_id,
        group_id=ctx.group_id,
        tenant_id=ctx.tenant_id,
        prompt_hash=agent.PROMPT_HASH,
    )
```

4c. Wrap the inbound review (replacing the bare call):

```python
    with with_span("REVIEW inbound", ids) as span:
        inbound = review_inbound(message, extract_inbound(message), history)
        span.set_attribute("refused", inbound.refused)
    log_event(log, "guide.turn.review", **ids, stage="inbound",
              refused=inbound.refused, reason=inbound.reason if inbound.refused else "")
    if inbound.refused:
        log.warning("refused by inbound: %s", inbound.reason)
        log_event(log, "guide.turn.output", **ids, raw_text="", final_text=inbound.reason,
                  refused_by="inbound", tokens_in=0, tokens_out=0, cost_usd=None, iterations=0)
        return { ...existing refusal dict unchanged... }
```

4d. Wrap the agent call (replacing `answer = agent.run(history, tools, message, at, attachments)`):

```python
    with with_span("CALL gemini", ids) as span:
        answer = agent.run(history, tools, message, at, attachments, capture=capture)
        span.set_attribute("gen_ai.request.model", agent.MODEL)
        span.set_attribute("gen_ai.usage.input_tokens", answer.tokens_in)
        span.set_attribute("gen_ai.usage.output_tokens", answer.tokens_out)
        span.set_attribute("iterations", capture.iteration)
        turn_cost = cost_usd(agent.MODEL, answer.tokens_in, answer.tokens_out)
        if turn_cost is not None:
            span.set_attribute("cost_usd", turn_cost)
```

4e. Wrap the outbound review the same shape as 4c (`stage="outbound"`, attribute `refused`), and on the refusal path emit:

```python
        log_event(log, "guide.turn.output", **ids, raw_text=answer.text, final_text=outbound.reason,
                  refused_by="outbound", tokens_in=answer.tokens_in, tokens_out=answer.tokens_out,
                  cost_usd=turn_cost, iterations=capture.iteration)
```

4f. On the passed path, before the final `return`:

```python
    log_event(log, "guide.turn.output", **ids, raw_text=answer.text, final_text=answer.text,
              refused_by=None, tokens_in=answer.tokens_in, tokens_out=answer.tokens_out,
              cost_usd=turn_cost, iterations=capture.iteration)
```

- [ ] **Step 5: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest tests/test_turn_instrumentation.py -v` → PASS
Then the whole suite: `python -m pytest` → PASS (existing turn tests must not notice the change).

- [ ] **Step 6: Root-span correlation in `main.py`.** In the `turn()` handler, right after `ctx = load_context(...)` succeeds, add:

```python
    from opentelemetry import trace as _trace  # module-top import is fine too

    _span = _trace.get_current_span()
    _span.set_attribute("turn_id", req.messageId)
    _span.set_attribute("group_id", req.groupId)
    _span.set_attribute("session_id", req.sessionId or "")
    _span.set_attribute("tenant_id", ctx.tenant_id)
```

(Put `from opentelemetry import trace` with main.py's imports and drop the local alias — shown inline here only for placement clarity.)

- [ ] **Step 7: Live smoke (optional but recommended).** With `GEMINI_API_KEY` set: `cd apps/guide-agent && python turn.py` — the fixture turn runs; confirm the process stays green and (with `LOG_PRETTY` unset) `guide.turn.model_input` / `guide.turn.output` JSON lines appear.

- [ ] **Step 8: Gates, commit**

```bash
git add apps/guide-agent/agent.py apps/guide-agent/turn.py apps/guide-agent/main.py \
  apps/guide-agent/tests/test_turn_instrumentation.py
git commit -m "feat(guide-agent): span the turn pipeline and capture model inputs, reviews and output"
```

**PR 2 done — hand to Abhinav to push and open the PR.**

---

## PR 3 — branch `feat/guide-obs-3-propagation`

### Task 6: Inject trace context + enqueue timestamp at the API seam

**Files:**
- Modify: `apps/api/src/helpers/guide-queue.ts` (interface + both dispatch paths)
- Test: `apps/api/tests/unit/guide-queue-dispatch-meta.test.ts`

**Interfaces:**
- Consumes: `@opentelemetry/api` (`context`, `propagation`) — already a dependency of apps/api.
- Produces: `withDispatchMeta(task: GuideTurnTask): GuideTurnTask` (exported, pure-ish — reads active OTel context + clock); `GuideTurnTask` gains optional `traceparent?: string; enqueuedAt?: string`. Task 7 (dispatcher) and Task 8 (queue-wait metric) consume these fields.

- [ ] **Step 1: Write the failing test** — `apps/api/tests/unit/guide-queue-dispatch-meta.test.ts` (follow the repo's unit-test conventions in `.claude/review-rules/unit-test-conventions.md`; mock nothing OTel — use the real API package, which no-ops without an SDK):

```typescript
import { withDispatchMeta, GuideTurnTask } from "../../src/helpers/guide-queue";

const task: GuideTurnTask = {
  messageId: "m1",
  groupId: "g1",
  sessionId: "s1",
  context: { any: "snapshot" },
};

describe("withDispatchMeta", () => {
  it("stamps enqueuedAt as ISO time and preserves the task fields", () => {
    const out = withDispatchMeta(task);
    expect(out.messageId).toBe("m1");
    expect(out.groupId).toBe("g1");
    expect(new Date(out.enqueuedAt!).toISOString()).toBe(out.enqueuedAt);
  });

  it("omits traceparent when no span is active (no-op OTel)", () => {
    const out = withDispatchMeta(task);
    expect(out.traceparent).toBeUndefined();
  });

  it("does not mutate its input", () => {
    withDispatchMeta(task);
    expect((task as any).enqueuedAt).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/api && pnpm test -- --testPathPattern=guide-queue-dispatch-meta`
Expected: FAIL — `withDispatchMeta` is not exported.

- [ ] **Step 3: Implement in `apps/api/src/helpers/guide-queue.ts`:**

3a. Add to imports: `import { context, propagation } from "@opentelemetry/api";`

3b. Extend the interface:

```typescript
export interface GuideTurnTask {
  messageId: string;
  groupId: string;
  sessionId: string | null;
  context: unknown;
  /** W3C trace context of the enqueuing request — read back by the agent so
   * one student turn is one trace across API → queue → agent. Set by
   * withDispatchMeta; absent when no span was active (tests, scripts). */
  traceparent?: string;
  /** Enqueue wall-clock time; the agent derives queue wait from it. */
  enqueuedAt?: string;
}
```

3c. Add the helper (above `enqueueGuideTurn`):

```typescript
/**
 * Stamp the task with trace context and enqueue time. In the body rather than
 * only headers because the local Redis path has no headers — the dispatcher
 * lifts `traceparent` back into a header, and Cloud Tasks carries it in both
 * (header for the auto-instrumented server, body as the shared fallback).
 */
export function withDispatchMeta(task: GuideTurnTask): GuideTurnTask {
  const carrier: Record<string, string> = {};
  propagation.inject(context.active(), carrier);
  return {
    ...task,
    ...(carrier.traceparent ? { traceparent: carrier.traceparent } : {}),
    enqueuedAt: new Date().toISOString(),
  };
}
```

3d. Use it in both paths. In `enqueueGuideTurn` change `const value = JSON.stringify(task);` → `const value = JSON.stringify(withDispatchMeta(task));` and change the first line `if (!IS_LOCAL) return await dispatchViaCloudTasks(task);` → `if (!IS_LOCAL) return await dispatchViaCloudTasks(withDispatchMeta(task));`. In `dispatchViaCloudTasks`, the `task` argument is now the stamped one; additionally add the header so FastAPI auto-instrumentation picks it up without touching the body:

```typescript
        headers: {
          "content-type": "application/json",
          ...(key ? { "x-internal-api-key": key } : {}),
          ...(task.traceparent ? { traceparent: task.traceparent } : {}),
        },
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/api && pnpm test -- --testPathPattern=guide-queue-dispatch-meta` → PASS
Then coverage + integration per pre-push (the script runs them).

- [ ] **Step 5: Gates, commit**

```bash
git checkout -b feat/guide-obs-3-propagation
git add apps/api/src/helpers/guide-queue.ts apps/api/tests/unit/guide-queue-dispatch-meta.test.ts
git commit -m "feat(api): stamp guide turn tasks with traceparent and enqueuedAt"
```

### Task 7: Dev dispatcher forwards the header; TurnRequest learns `enqueuedAt`

**Files:**
- Modify: `apps/guide-agent/dev/dispatcher.py` (`handle()`)
- Modify: `apps/guide-agent/main.py` (`TurnRequest`)
- Test: `apps/guide-agent/tests/test_dispatch_meta.py`

**Interfaces:**
- Consumes: task JSON fields `traceparent`, `enqueuedAt` from Task 6.
- Produces: dispatcher POSTs with a `traceparent` header when present; `TurnRequest.enqueuedAt: str | None` (camelCase — apps/api writes it) available to Task 8's queue-wait metric. Also exports `dispatch_headers(task: dict) -> dict` from dispatcher for testability.

- [ ] **Step 1: Write the failing test** — `apps/guide-agent/tests/test_dispatch_meta.py`:

```python
"""The local dispatcher forwards trace context the way Cloud Tasks does —
as a header — and TurnRequest tolerates + exposes enqueuedAt."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "dev"))

from dispatcher import dispatch_headers  # noqa: E402
from main import TurnRequest  # noqa: E402


def test_traceparent_becomes_header():
    headers = dispatch_headers({"messageId": "m1", "traceparent": "00-aa-bb-01"})
    assert headers["traceparent"] == "00-aa-bb-01"


def test_no_traceparent_no_header():
    assert "traceparent" not in dispatch_headers({"messageId": "m1"})


def test_turnrequest_accepts_enqueued_at():
    req = TurnRequest(messageId="m1", groupId="g1", context={}, enqueuedAt="2026-09-09T10:00:00.000Z")
    assert req.enqueuedAt == "2026-09-09T10:00:00.000Z"


def test_turnrequest_enqueued_at_optional():
    assert TurnRequest(messageId="m1", groupId="g1", context={}).enqueuedAt is None
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_dispatch_meta.py -v`
Expected: FAIL — `dispatch_headers` / `enqueuedAt` don't exist.

- [ ] **Step 3: Implement.** In `dev/dispatcher.py` add above `handle()`:

```python
def dispatch_headers(task: dict) -> dict:
    """The one header Cloud Tasks would have carried that matters locally:
    trace context. apps/api stamps it into the task body (the Redis path has
    no headers); lifting it back out here means the agent's FastAPI
    instrumentation sees the same header in every environment."""
    tp = task.get("traceparent")
    return {"traceparent": tp} if tp else {}
```

and change the POST in `handle()`:

```python
    res = httpx.post(f"{AGENT_URL}/turn", json=task, timeout=TURN_TIMEOUT, headers=dispatch_headers(task))
```

In `main.py`'s `TurnRequest`, after `sessionId`:

```python
    # Stamped by apps/api at enqueue; queue wait is derived from it. Optional
    # because replayed/hand-crafted tasks won't have it.
    enqueuedAt: str | None = None
```

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest tests/test_dispatch_meta.py -v` → PASS, then full `python -m pytest` → PASS.

- [ ] **Step 5: End-to-end propagation smoke (manual, documented result in the PR).** Run the local stack (API + agent + dispatcher + Redis), send a guide message from the dashboard, and confirm the agent's `POST /turn` log line carries the same `trace_id` as the API's enqueue log. This is the one behavior no unit test covers honestly.

- [ ] **Step 6: Gates, commit**

```bash
git add apps/guide-agent/dev/dispatcher.py apps/guide-agent/main.py apps/guide-agent/tests/test_dispatch_meta.py
git commit -m "feat(guide-agent): accept propagated trace context and enqueuedAt from the queue"
```

**PR 3 done — hand to Abhinav to push and open the PR.**

---

## PR 4 — branch `feat/guide-obs-4-metrics`

### Task 8: Metric instruments + recording

**Files:**
- Modify: `apps/guide-agent/telemetry.py` (instrument definitions at module level)
- Modify: `apps/guide-agent/turn.py`, `apps/guide-agent/main.py`, `apps/guide-agent/capture.py` (recording sites)
- Test: `apps/guide-agent/tests/test_metrics.py`

**Interfaces:**
- Consumes: `enqueuedAt` (Task 7), verdicts/tokens/cost already in scope at each site.
- Produces: module-level instruments in `telemetry.py`: `turn_duration` (histogram, s), `turn_tokens` (counter, attr `direction: in|out`), `turn_cost_usd` (counter), `review_rejections` (counter, attr `stage: inbound|outbound`), `tool_errors` (counter, attr `tool`), `queue_wait` (histogram, ms).

- [ ] **Step 1: Write the failing test** — `apps/guide-agent/tests/test_metrics.py`:

```python
"""Instruments exist at module level (rule 4: never created per-request) and
the queue-wait math parses ISO timestamps defensively."""

import telemetry
from telemetry import queue_wait_ms


def test_instruments_are_module_level():
    for name in ("turn_duration", "turn_tokens", "turn_cost_usd",
                 "review_rejections", "tool_errors", "queue_wait"):
        assert hasattr(telemetry, name), f"missing instrument {name}"


def test_queue_wait_ms_parses_iso():
    assert queue_wait_ms("2026-09-09T10:00:00.000Z", now_ms=None) is not None


def test_queue_wait_ms_none_on_missing_or_garbage():
    assert queue_wait_ms(None) is None
    assert queue_wait_ms("not-a-time") is None
```

- [ ] **Step 2: Run to verify failure**

Run: `cd apps/guide-agent && python -m pytest tests/test_metrics.py -v`
Expected: FAIL — names missing.

- [ ] **Step 3: Implement.** In `telemetry.py` add at module level (bottom of file — the API meter no-ops until `setup_telemetry` installs the provider, so module-level creation is safe in every mode):

```python
from opentelemetry import metrics as _metrics
import datetime

_meter = _metrics.get_meter("guide-agent")

# RED + business instruments. Attributes stay bounded enums — ids live on
# spans and logs (packages/telemetry rule 3 applies here too).
turn_duration = _meter.create_histogram("guide.turn.duration", unit="s", description="End-to-end turn time inside the agent")
turn_tokens = _meter.create_counter("guide.turn.tokens", description="Model tokens, attr direction=in|out")
turn_cost_usd = _meter.create_counter("guide.turn.cost", unit="{USD}", description="Model spend derived from tokens")
review_rejections = _meter.create_counter("guide.review.rejection.count", description="Turns held back, attr stage=inbound|outbound")
tool_errors = _meter.create_counter("guide.tool.error.count", description="Tool executions that raised, attr tool")
queue_wait = _meter.create_histogram("guide.queue.wait", unit="ms", description="enqueue → dispatch latency")


def queue_wait_ms(enqueued_at: str | None, now_ms: float | None = None) -> float | None:
    """ms between the API's enqueue stamp and now; None when absent/garbage —
    a missing stamp must cost nothing."""
    if not enqueued_at:
        return None
    try:
        t = datetime.datetime.fromisoformat(enqueued_at.replace("Z", "+00:00"))
    except ValueError:
        return None
    now = now_ms if now_ms is not None else datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000
    return max(now - t.timestamp() * 1000, 0.0)
```

Recording sites:
- `main.py` `turn()`: at the top record `wait = queue_wait_ms(req.enqueuedAt)`; `if wait is not None: queue_wait.record(wait)`. Wrap the whole handler body's timing: `start = time.monotonic()` first line, and just before `return answer`: `turn_duration.record(time.monotonic() - start)`. (Add `import time` and the telemetry imports.)
- `turn.py`: where verdicts refuse — `review_rejections.add(1, {"stage": "inbound"})` / `{"stage": "outbound"}`; after `cost_usd` computation on every path that ran the model — `turn_tokens.add(answer.tokens_in, {"direction": "in"})`, `turn_tokens.add(answer.tokens_out, {"direction": "out"})`, and `if turn_cost is not None: turn_cost_usd.add(turn_cost)`.
- `capture.py` `_finish_tool`: when `error is not None` — `tool_errors.add(1, {"tool": name})` (import from `telemetry`).

- [ ] **Step 4: Run to verify pass**

Run: `cd apps/guide-agent && python -m pytest` → all PASS.

- [ ] **Step 5: Gates, commit**

```bash
git checkout -b feat/guide-obs-4-metrics
git add apps/guide-agent/telemetry.py apps/guide-agent/turn.py apps/guide-agent/main.py \
  apps/guide-agent/capture.py apps/guide-agent/tests/test_metrics.py
git commit -m "feat(guide-agent): RED + cost metrics for turns, reviews, tools and queue wait"
```

### Task 9: Runbook — "how to read a turn / a session"

**Files:**
- Modify: `apps/guide-agent/README.md` (new `## Observability` section)

**Interfaces:** none — documentation of everything above.

- [ ] **Step 1: Write the section.** Content requirements (write it out fully, in the README's existing voice):
  - Env vars table: `OTEL_SDK_DISABLED`, `GUIDE_CAPTURE_DISABLED`, `OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `GCP_PROJECT_ID`, `LOG_LEVEL`, `LOG_PRETTY` — one line each, defaults stated.
  - "Read one turn": Cloud Trace → filter `turn_id=<messageId>` → span tree → click through to logs; the five capture events and what each contains; reconstructing model call N as `model_input` + deltas 1..N.
  - "Read one session": Logs Explorer query `jsonPayload.session_id="<id>"` sorted ascending; same filter in Trace list.
  - "Cost": where per-turn cost lives (span attr + `guide.turn.output`), where aggregate lives (`guide.turn.cost` metric), and that `costs.py` must gain a row when `GUIDE_MODEL` changes.
  - Deployment note: Cloud Run service account needs `roles/telemetry.metricsWriter`/trace agent roles (mirror whatever the api service uses — check its Terraform/deploy scripts and cite the same roles); `GCP_PROJECT_ID` must be set for log↔trace linking.

- [ ] **Step 2: Verify claims against the code** — every env var, event name, metric name and attribute in the section must exist in the merged code (grep each one).

- [ ] **Step 3: Gates, commit**

```bash
git add apps/guide-agent/README.md
git commit -m "docs(guide-agent): observability runbook — reading turns, sessions and cost"
```

**PR 4 done — hand to Abhinav to push and open the PR.**

---

## Self-review notes (already applied)

- Spec coverage: end-to-end trace (T2, T6, T7), verbatim input capture + deltas (T4, T5), session correlation attrs (T2 helper, T4 ids, T5 main.py), cost per-turn + aggregate (T3, T5, T8), review verdict logs (T5), metrics list (T8), runbook (T9), kill switches (T2, T4). Queue-wait needed `enqueuedAt` — added to T6/T7, consumed in T8.
- Known judgment calls an implementer may hit: exact `on_chat_model_start` kwargs differ across langchain-core minor versions (accept `**kwargs`, done); `_AuthedMetricExporter.export` signature may differ by SDK version — match the installed version's signature; redact-pattern sample in T4's test may need a shape `redact.py` matches. None of these change the design.
