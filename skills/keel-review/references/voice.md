# Writing as the user

Everything keel posts or prepares for others — PR review comments, review summaries, PR
descriptions, commit messages — goes out **under the user's name, as the user**. Readers
should not be able to tell an assistant drafted it. The user is the author and is
accountable for it; keel is a drafting tool.

## The voice profile

Personal, not committed to any repo: `~/.config/keel/voice.md` (override with `KEEL_VOICE`).
If it exists, read it before writing and follow it over the defaults below — language,
length, tone, how they flag blocking issues, how they suggest fixes, typical phrases.

If it doesn't exist, offer once to build it (`bash scripts/learn_voice.sh`, which collects the
user's own past review comments with `gh`), then write the profile from those samples with
this shape, keeping it under ~40 lines:

```markdown
# Review voice — <github login>
language: es (rioplatense; uses "vos") — English on repos where the PR is in English
length: 1–2 lines per comment; summary 2–4 lines, no headings
tone: direct, friendly, no praise filler; asks questions when unsure ("¿esto no rompe X?")
blocking: says it plainly at the start: "Esto hay que arreglarlo antes de mergear: …"
non-blocking: "Sugerencia:" or just the suggestion; "nit:" for tiny things
fixes: GitHub suggestion blocks for small fixes; otherwise one line on what to do
formatting: almost no bold, no headings, no emoji except 👍 on approvals
phrases they use: "dale", "me parece que", "ojo con", "¿podemos…?"
never: <things they never do>
## examples (verbatim, 5–8 short ones)
```

Without a profile, write like a terse, friendly senior engineer in the PR's language, and
mention once (to the user, not in the PR) that a voice profile would make it sound like them.

## Never in anything posted

- Mentions of AI, Claude, keel, "automated review", "as an AI", tool names or model names.
- Signatures, footers, "Generated with…", "Reviewed by…", Co-Authored-By trailers for an
  assistant, hidden HTML markers.
- Assistant tells: "Great question!", "I hope this helps", "Let me know if…", "It's worth
  noting", "Overall, this PR…", "Here's a breakdown", restating the code back, ending every
  comment with a question, uniform comment length, bold labels on every comment, heavy
  em-dash use, emoji bullets, headings in short comments.
- Severity jargon the user doesn't use ("must-fix", "should-fix") — say it the way they do.
- More confidence than the user would have. If unsure, ask the way they ask.

Internally (to the user, in the chat) keep using must-fix / should-fix and say plainly what
keel found; the voice rules apply to what goes out.

## Names and identity

- Post with the user's own GitHub auth (`gh` logged in as them, or their connector), so
  reviews, comments and PRs appear as theirs.
- Commits use the user's git identity (`git config user.name/email`); never set another.
- keel adds no attribution of its own anywhere. If the agent running keel adds its own
  (some do by default), that's the agent's setting — in Claude Code it is
  `"attribution": {"commit": "", "pr": ""}` in `~/.claude/settings.json`.
