# Heartbeat Guide

When you receive a heartbeat poll (message matches the configured heartbeat prompt), don't just reply `HEARTBEAT_OK` every time. Use heartbeats productively!

Default heartbeat prompt:
`Read HEARTBEAT.md if it exists (workspace context). Follow it strictly. Do not infer or repeat old tasks from prior chats. If nothing needs attention, reply HEARTBEAT_OK.`

You are free to edit `HEARTBEAT.md` with a short checklist or reminders. Keep it small to limit token burn.

## Heartbeat vs Cron: When to Use Each

**Use heartbeat when:**

- Multiple checks can batch together (inbox + calendar + notifications in one turn)
- You need conversational context from recent messages
- Timing can drift slightly (every ~30 min is fine, not exact)
- You want to reduce API calls by combining periodic checks

**Use cron when:**

- Exact timing matters ("9:00 AM sharp every Monday")
- Task needs isolation from main session history
- You want a different model or thinking level for the task
- One-shot reminders ("remind me in 20 minutes")
- Output should deliver directly to a channel without main session involvement

**Tip:** Batch similar periodic checks into `HEARTBEAT.md` instead of creating multiple cron jobs. Use cron for precise schedules and standalone tasks.

## Things to Check

Rotate through these, 2-4 times per day:

- **Emails** — Any urgent unread messages?
- **Calendar** — Upcoming events in next 24-48h?
- **Mentions** — Twitter/social notifications?
- **Weather** — Relevant if your human might go out?

## Track Your Checks

Write to `memory/heartbeat-state.json`:

```json
{
  "lastChecks": {
    "email": 1703275200,
    "calendar": 1703260800,
    "weather": null
  }
}
```

## When to Reach Out

**Do reach out when:**

- Important email arrived
- Calendar event coming up (<2h)
- Something interesting you found
- It's been >8h since you said anything

**Stay quiet (HEARTBEAT_OK) when:**

- Late night (23:00-08:00) unless urgent
- Human is clearly busy
- Nothing new since last check
- You just checked <30 minutes ago

## Proactive Work You Can Do Without Asking

- Read and organize memory files
- Check on projects (git status, etc.)
- Update documentation
- Commit and push your own changes
- Review and update MEMORY.md (see [memory-system.md](memory-system.md))

## The Goal

Be helpful without being annoying. Check in a few times a day, do useful background work, but respect quiet time.
