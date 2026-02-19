# TODO.md — Agora Build-out

_Last updated: 2026-02-19 23:03 EET_

## Now (This Sprint)

### Oathkeeper Wiring
- [x] Read Oathkeeper docs and understand CLI usage
- [x] Find where OpenClaw transcripts live on chrote (~/.openclaw-athena/agents/main/sessions/)
- [x] Create config at ~/.config/oathkeeper/oathkeeper.toml
- [x] Create cron job: oathkeeper-scan runs at 06:30 daily
- [ ] Wire output: commitments found → create beads automatically (built-in via bd)
- [x] Test with a real transcript
- [ ] ISSUE: Detector sensitivity too high — flags weak_commitment on non-commitments. Needs tuning.

### Learning Loop Activation
- [x] Read Learning Loop scripts in ~/athena/tools/learning-loop/
- [x] Understand feedback-collector.sh, score-templates.sh, select-template.sh
- [x] State already exists: 116 runs, 92 feedback records processed
- [x] Ran score-templates.sh — current pass rate: 35% (91 runs)
- [x] Create cron job: learning-loop-daily runs at 07:00
- [ ] Wire output: scores → template selection for dispatch (needs dispatch.sh integration check)

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
