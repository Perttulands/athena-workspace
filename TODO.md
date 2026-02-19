# TODO.md — Agora Build-out

_Last updated: 2026-02-19 23:03 EET_

## Now (This Sprint)

### Oathkeeper Wiring
- [ ] Read Oathkeeper docs and understand CLI usage
- [ ] Find where OpenClaw transcripts live on chrote
- [ ] Create cron job: scan transcripts daily for unverified commitments
- [ ] Wire output: commitments found → create beads automatically
- [ ] Test with a real transcript

### Learning Loop Activation
- [ ] Read Learning Loop scripts in ~/athena/tools/learning-loop/
- [ ] Understand feedback-collector.sh, score-templates.sh, select-template.sh
- [ ] Set up state/runs/ with at least one real run record
- [ ] Create cron job: process runs → update scores
- [ ] Wire output: scores → template selection for dispatch

## Next

### Relay Backbone
- [ ] Read Relay docs and CLI
- [ ] Design message schema for dispatch (what replaces dispatch.sh)
- [ ] Prototype: Athena sends dispatch message via Relay
- [ ] Prototype: Agent completion triggers Relay message back
- [ ] Migrate one dispatch flow end-to-end
- [ ] Document the new flow

### Senate Design
- [ ] Write Senate PRD (purpose, scope, process)
- [ ] Design deliberation protocol (how agents argue, how verdicts work)
- [ ] Define case types (rule evolution, architecture, disputes)
- [ ] Create senate/ repo structure
- [ ] Implement first case: a Truthsayer rule amendment

## Blocked / Waiting

_(Nothing currently blocked)_

## Done

- [x] Cron jobs updated for chrote paths
- [x] HEARTBEAT.md set up with work tracking
- [x] Overnight work cron (23:00, 02:00, 05:00)
- [x] Verified bd and truthsayer working
- [x] system-architecture.md and JUDGMENT.md migrated (Mercury)

## Notes

- Can merge to main after Centurion passes (Perttu approved)
- Use sessions_spawn for sub-agent work
- Update memory/ daily with progress
- If blocked, note in HEARTBEAT.md and stop
