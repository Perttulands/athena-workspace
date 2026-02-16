# Memory System

You wake up fresh each session. These files are your continuity.

## Two Types of Memory

### Daily Notes: `memory/YYYY-MM-DD.md`

Raw logs of what happened. Create `memory/` directory if it doesn't exist.

- Capture decisions, context, things to remember
- Skip secrets unless asked to keep them
- Written during the session as things happen

### Long-Term: `MEMORY.md`

Your curated memories, like a human's long-term memory.

- **ONLY load in main session** (direct chats with Perttu)
- **DO NOT load in shared contexts** (Discord, group chats, sessions with other people)
- This is for **security** — contains personal context that shouldn't leak to strangers
- Write significant events, thoughts, decisions, opinions, lessons learned
- This is your curated memory — the distilled essence, not raw logs
- Over time, review daily files and update MEMORY.md with what's worth keeping

## Write It Down - No "Mental Notes"!

**Memory is limited** — if you want to remember something, WRITE IT TO A FILE.

"Mental notes" don't survive session restarts. Files do.

When to write:
- Someone says "remember this" → update `memory/YYYY-MM-DD.md` or relevant file
- You learn a lesson → update AGENTS.md, TOOLS.md, or the relevant skill
- You make a mistake → document it so future-you doesn't repeat it
- A pattern works well → capture it in the relevant skill or doc
- A pattern fails → write it down immediately, then update the doc that should have prevented it

**Text > Brain** 📝

**The moment you learn it, write it.** Not later. Not next heartbeat. Now.

## Startup Reading

Before doing anything else:

1. Read `SOUL.md` — this is who you are
2. Read `USER.md` — this is who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. **If in MAIN SESSION** (direct chat with your human): Also read `MEMORY.md`

Don't ask permission. Just do it.

**Keep startup files lean.** If total startup reading exceeds ~500 lines, something needs pruning. Distilled > verbose. Every line must earn its place.

## Memory Maintenance

Periodically (every few days), use a heartbeat to:

1. Read through recent `memory/YYYY-MM-DD.md` files
2. Identify significant events, lessons, or insights worth keeping long-term
3. Update `MEMORY.md` with distilled learnings
4. Remove outdated info from MEMORY.md that's no longer relevant

Think of it like a human reviewing their journal and updating their mental model. Daily files are raw notes; MEMORY.md is curated wisdom.
