# Reusable prompt — the Polymath deck style

Paste the block below, swap the bracketed parts, and you get the same deck treatment.
Everything outside brackets is what produces the *style*; everything inside brackets is
what changes per deck.

---

## The prompt

> Build me a PowerPoint (.pptx), 13.333 × 7.5 inches, using pptxgenjs. Validate it and do a
> visual QA pass on every rendered slide before you give it to me.
>
> **Audience and job.** [Who is in the room, what they can decide, how long the slot is.]
> Write it as evidence, not a pitch — every number must come from [the source], and if a
> number can't be sourced, leave it out and tell me.
>
> **Design system — hold this constant across every slide:**
> - Palette: one dominant dark (deep navy-ink `0E2233`), two supporting blues (`16405F`,
>   `1C7293`), one sharp accent used sparingly (amber `E0A126`), white ground, and a very
>   light card tint (`F1F5F8`). Dark slides for the title, section moments and the close;
>   light slides for content.
> - Type: a serif for headings (Cambria) paired with a sans for body (Calibri). Titles
>   34pt bold, section labels 20–24pt, body 12–15pt. Nothing smaller than 10pt.
> - Motif: rounded cards with a subtle tint fill. No accent stripes, no colour bars, no
>   underlines beneath titles, no emoji, no drop shadows.
> - **No source notes, provenance lines or as-of caveats anywhere on the page** — nothing
>   like "figures as of September 2026", "read from the live system", "based on data
>   available at the time of writing". Give me the sourcing and the caveats in chat, not
>   on the slide. One publication date on the cover is enough.
> - Every slide carries the same three-part header: a small uppercase amber eyebrow
>   (letter-spaced), a large serif title, and one line of grey standfirst underneath.
> - 0.7" margins, consistent gaps, and every slide gets a visual element — a card grid,
>   a chart, a stat row, a numbered process, or a two-column split. No slide is plain
>   title-and-bullets.
>
> **Vary the layouts.** Rotate between: numbered card rows, a stat grid of big numbers with
> small labels, a horizontal bar chart, a 2×3 card grid, a five-step numbered process, a
> two-column split with a dark panel on one side, and a three-column comparison. Never use
> the same layout twice in a row.
>
> **Charts:** horizontal bars, single colour from the palette, value labels on, axis
> starting at zero, no legend, no chart title, faint gridlines only.
>
> **Speaker notes on every slide** — what to emphasise, what to slow down on, and what not
> to claim.
>
> **Structure:** [open with the problem the audience already lives → what we built →
> the evidence → each module in turn → what it means for them → the rollout path → close
> on two or three concrete asks].
>
> Flag anything I should not say out loud, and tell me which claims you could not verify.

---

## Why each part of that prompt matters

| The instruction | What it prevents |
|---|---|
| Fixed hex palette, one accent | Generic blue decks, or five competing colours |
| Serif heading + sans body, sizes named | Flat typography where the title barely outranks the body |
| "No accent stripes, no colour bars, no emoji" | The tells that make a deck read as AI-generated |
| The eyebrow / title / standfirst header | Every slide reads as the same document |
| "Vary the layouts", with the list | Twenty identical bullet slides |
| Chart rules | Default chart styling — dated palette, no labels, negative axis |
| "Evidence, not a pitch" | Confident claims with nothing behind them |
| "Flag what I should not say" | Getting caught out in the room |
| "Visual QA every rendered slide" | Text overflowing its box, which is the most common defect |
| "No source notes or as-of caveats" | Defensive footnotes that make confident content look hedged |

## Shortcut for next time

You don't have to paste the whole thing. This gets you most of the way:

> Same deck style as the JNTU one — navy/amber, Cambria + Calibri, card motif, eyebrow +
> serif title + standfirst on every slide, varied layouts, speaker notes, visual QA.
> This time it's [topic] for [audience], [N] slides.

The one thing worth repeating every time regardless: **"every number must be sourced, and
flag anything I shouldn't say."** That is what makes the deck safe to walk into a room with.

## If you want it permanent

Ask for it to be saved as a skill, and the style becomes a slash command you invoke by
name instead of a prompt you paste — the palette, type, layout rules and QA steps all
travel with it.
