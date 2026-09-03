# Workflow — working with AI on deliverables

The path I follow. Mistakes are logged in `COMMON-MISTAKES.md`; deck style prompts in `PPT-style-prompt.md`.

---

**Why gates:** the cost of changing one thing multiplies at every stage.

| Change | Costs |
|---|---|
| A line in an outline | seconds |
| A paragraph in a content file | a minute |
| A slide in a built deck | ten minutes |
| The argument of a finished deck | a morning |

**So: make every decision at the cheapest stage where it can be made.**
Almost all wasted time is a Gate 1 decision made at Gate 3.

### Gate 0 — Brief · 5 min, nothing built yet

Answer in chat before asking for any file:

1. Who is in the room, and what can they decide?
2. Whose voice — mine, my company's, or the client presenting their own work?
3. What is the **one thing** they must leave believing?
4. What must not be said?
5. Where do the facts come from, and who verifies them?
6. Format, length, where the file lands.

If I can't answer #3, I'm not ready to ask for a deck. I'm still thinking.

### Gate 1 — Outline · in chat, no files

A numbered list, one line per slide, each stating **the claim that slide makes** — not its title.
"Adoption is real and measurable" is a claim. "Adoption" is a topic.

Check: does the sequence argue? Would cutting a line hurt? Can I support every claim?

Cheapest place in the process — iterate freely. Two rounds max.
Close with: **"Outline approved. Now the content."**

### Gate 2 — Content · one text file, no slides

Every headline, body line and number in one plain file, with the source of each number.
Read it as prose. Fix wording here. Delete anything I couldn't defend.

Last cheap moment. Two rounds max.
Close with: **"Content approved. Now build it."**

### Gate 3 — Build · format applied

Generator turns the content file into the deck. Cosmetic issues only — overflow, spacing,
chart type, colour.

> **The rule that matters most:** never fix a Gate 1 or Gate 2 problem at Gate 3.
> If the argument is wrong, go back to Gate 1 and regenerate. Do not patch slides one by one.

### Five things no model can do for me

1. Decide the audience and the voice.
2. Supply or verify the facts.
3. Say what must not be said.
4. Name the one thing the audience must leave believing.
5. Decide when it's good enough and stop.

### Stop rules

- **Two revision rounds per gate.** A third means the previous gate was wrong — go back, don't
  iterate forward.
- **Batch feedback.** All changes in one message.
- **Never say "make it better".** Say what's wrong and what right looks like.
- **Reuse, don't regenerate:** `Use the generator in co-work_outputs/<previous-task>/_source/.
  New content file for <topic>. Same structure, same style. Do not redesign.`

### Pre-flight — 20 seconds before any request

- [ ] Audience and voice named?
- [ ] The one thing it must achieve?
- [ ] Facts in hand, or source stated?
- [ ] Said what must not be said?
- [ ] Pointed at the generator to reuse?

If any box is empty, that's the message to send — not the request.
