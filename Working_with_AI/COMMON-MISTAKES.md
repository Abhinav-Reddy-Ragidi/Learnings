# Common mistakes

What went wrong, and the rule it produced. The path itself is in `WORKFLOW.md`.

Add an entry only when the same correction has been needed twice. Delete entries whose rule has
become automatic.

### Deliverables written into the source repository
Seven generated files ended up in a code repo, three of them superseded versions nobody deleted.
**Rule:** outputs go to `co-work_outputs/<date>_<task-slug>/`; source repos stay clean.

### "Figures as of September 2026" printed under a chart
Uncertainty about the numbers was hedged on the slide instead of raised in chat. A confident
document footnoting itself invites the scrutiny it's trying to avoid.
**Rule:** caveats in chat, never in the deliverable. One publication date on the cover is enough.

### A row count labelled as a headcount
9,337 enrolment rows was labelled "student enrolments" and led the slide, reading as 9,337
students — more than the institution has.
**Rule:** the label states the unit the query actually counted. People need `COUNT(DISTINCT user_id)`.

### Invented supporting claims
"The subjects that historically account for the largest share of first-year backlogs" was written
to give a number meaning. No backlog data existed.
**Rule:** no claim without a source, including the framing around a real number.

### A chart that carried no signal
A bar chart of enrolments by subject told the audience only that first-year cohorts are large —
true of every college. Depth data was available and unused.
**Rule:** prefer a metric that could have come out differently.

### Product vocabulary in a client-facing document
"Course → module → activity", "modules", "activated per college" — internal data-model language
in a document for a Vice-Chancellor.
**Rule:** describe what a person does, not how the system is built.

### Renaming mid-project
Engineering Labs → Polymath → VNRVJIET changed the filenames, orphaning the earlier files on disk.
**Rule:** fix the filename once, at the brief stage.

### Three full rewrites from a missing brief
Built as a product document, rebuilt as a showcase deck, rebuilt again in the client's voice —
because audience and voice were never settled before drafting.
**Rule:** the brief is answered before the first draft. Cost more than every other mistake combined.

### Over-delivering against the ask
Asked for one workflow file; produced five files and two hosted pages.
**Rule:** build exactly what was asked. Suggest extras in chat; don't create them.
