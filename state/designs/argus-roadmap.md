# Argus Roadmap

_Generated: 2026-02-19_

## 1. Current State Summary

Argus is a **functional ops watchdog** running every 5 minutes via systemd with the following capabilities:

### Working Infrastructure
| Component | Status | Notes |
|-----------|--------|-------|
| Systemd timer | ✅ | 5-minute cycle |
| Collectors | ✅ | Disk, memory, CPU, swap, processes, services |
| LLM analysis | ✅ | Claude Haiku with structured prompt |
| Actions | ✅ | 5 allowlisted: restart_service, kill_pid, kill_tmux, alert, log |
| Telegram alerts | ✅ | Retry on failure, hostname prepended |
| Security | ✅ | Input sanitization, systemd hardening, no arbitrary exec |
| Self-monitoring | ✅ | Alerts after 3 consecutive failures |

### Deterministic Behaviors
- Orphan `node --test` processes auto-killed after 3 detections (no LLM)
- Log rotation at 10MB (3 backups)
- Disk space guard skips LLM call if < 100MB free

### Location & Deployment
- **Path:** `/home/chrote/athena/tools/argus`
- **Repo:** `github.com/Perttulands/argus`
- **Service:** `argus.service` + `argus.timer`

---

## 2. Target State Summary

Per the PRD, Argus should evolve from reactive alerting to **autonomous problem management**:

### Self-Healing Matrix
| Problem | Target Action |
|---------|---------------|
| Service down | Restart (max 3 attempts, backoff) |
| Orphan processes | Kill (partially done) |
| Disk > 90% | Clean temp directories, alert |
| Memory > 90% | Identify memory hog, alert |
| Swap thrashing | Alert + root cause identification |

### Problem Management
- **Registry:** All detections logged to `state/problems.jsonl`
- **Bead Integration:** Auto-create beads via `bd create` for issues requiring human attention
- **Pattern Analysis:** Detect recurring problems over time
- **Historical Dashboard:** Track server health trends

### Independence
- Works without Relay (resilience requirement)
- Optional Relay integration for summaries when available

---

## 3. Gap Analysis

| Feature | Current | Target | Gap Severity |
|---------|---------|--------|--------------|
| Problem registry | ❌ Absent | `state/problems.jsonl` with timestamp, severity, action, bead | **High** — No persistent record |
| Bead creation | ❌ Absent | Auto-create via `bd create --title "[argus]..."` | **High** — No task tracking |
| Disk cleanup | ❌ Alert only | Clean temp dirs + alert | **Medium** — Manual intervention required |
| Memory hog ID | ❌ Generic alert | Identify specific process + alert | **Medium** — Diagnostic quality |
| Swap thrashing | ❌ Alert only | Root cause + alert | **Medium** — Diagnostic quality |
| Restart backoff | ⚠️ Basic | Max 3 attempts with exponential backoff | **Low** — Partial implementation |
| Historical analysis | ❌ Absent | Pattern detection over time | **Medium** — Reactive vs predictive |
| Dashboard | ❌ Absent | Health trends visualization | **Low** — Nice-to-have |
| Relay integration | ❌ Absent | Optional summary routing | **Low** — Works without |

### Critical Path
The **problem registry** is foundational — bead creation, pattern analysis, and historical tracking all depend on structured problem data. This is task #1.

---

## 4. Implementation Roadmap

### Phase 1: Problem Infrastructure (Foundation)

#### ARG-001: Implement Problem Registry
**Description:** Create `state/problems.jsonl` and update `argus.sh` to log every detected problem with structured metadata before taking action.

**Schema:**
```json
{
  "ts": "2026-02-19T23:30:00Z",
  "severity": "critical|warning|info",
  "type": "disk|memory|service|process|swap",
  "description": "Service gateway is down",
  "action_taken": "restart_service:gateway",
  "action_result": "success|failure|skipped",
  "bead_id": null,
  "host": "landmass"
}
```

**Dependencies:** None  
**Complexity:** S  
**Definition of Done:**
- [ ] `state/problems.jsonl` created on first detection
- [ ] Every LLM-triggered action logs a problem record
- [ ] Deterministic orphan kills also log records
- [ ] Schema documented in README
- [ ] `jq` queries work on the file (valid JSONL)

---

#### ARG-002: Implement Bead Creation
**Description:** When Argus detects a problem requiring human attention (action failed, recurring issue, or no automatic fix available), create a bead via `bd create`.

**Triggering conditions:**
1. Action attempted but failed
2. Same problem detected 3+ times in 24 hours
3. Problem type has no automatic remediation

**Dependencies:** ARG-001 (needs problem registry to detect recurrence)  
**Complexity:** M  
**Definition of Done:**
- [ ] `create_bead()` function added to `actions.sh`
- [ ] Bead title format: `[argus] <type>: <description>`
- [ ] Bead body includes diagnostic context
- [ ] `bead_id` stored in problem record
- [ ] Deduplication: don't create bead if open bead exists for same problem
- [ ] Works when `bd` is available; graceful skip otherwise

---

#### ARG-003: Add Problem Deduplication Logic
**Description:** Implement deduplication to prevent alert/bead spam for ongoing issues. Track problem identity and suppress re-alerting within a configurable window.

**Dependencies:** ARG-001  
**Complexity:** S  
**Definition of Done:**
- [ ] Problem identity key: `${type}:${description_hash}`
- [ ] Configurable suppression window (default: 1 hour)
- [ ] Suppressed alerts logged with `action_result: suppressed`
- [ ] Tests for dedup logic

---

### Phase 2: Self-Healing Expansion

#### ARG-004: Implement Disk Cleanup Action
**Description:** When disk usage > 90%, automatically clean known-safe temp directories before alerting.

**Safe targets:**
- `/tmp/*` older than 7 days
- `/var/tmp/*` older than 7 days
- `~/.cache/*/` selected subdirs
- Log archives matching `*.log.[0-9].gz`

**Dependencies:** ARG-001 (logging)  
**Complexity:** M  
**Definition of Done:**
- [ ] `clean_disk` action added to allowlist
- [ ] Only cleans files older than threshold (configurable)
- [ ] Logs bytes reclaimed in problem record
- [ ] Alert sent with before/after percentages
- [ ] Never touches paths outside safelist (hardcoded, not configurable)

---

#### ARG-005: Implement Memory Hog Identification
**Description:** When memory > 90%, identify the top memory consumer and include it in the alert with actionable context.

**Dependencies:** ARG-001  
**Complexity:** S  
**Definition of Done:**
- [ ] Alert includes: process name, PID, RSS, %MEM, runtime
- [ ] If process matches kill allowlist, offer kill action to LLM
- [ ] Problem record includes hog details
- [ ] Works correctly with cgroups/containers

---

#### ARG-006: Implement Restart Backoff
**Description:** Track restart attempts per service and implement exponential backoff to prevent restart loops.

**Backoff schedule:**
1. First attempt: immediate
2. Second attempt: wait 1 minute
3. Third attempt: wait 5 minutes
4. Fourth+: create bead, stop retrying for 1 hour

**Dependencies:** ARG-001, ARG-002  
**Complexity:** M  
**Definition of Done:**
- [ ] Restart attempts tracked in state file
- [ ] Backoff timing enforced
- [ ] After 3 failures, bead created automatically
- [ ] Cooldown resets after 1 hour of success
- [ ] State persists across Argus restarts

---

#### ARG-007: Implement Swap Thrashing Detection
**Description:** Detect swap thrashing (high swap I/O with low benefit) and identify the likely cause.

**Metrics:**
- `vmstat` swap in/out rates
- Memory pressure indicators
- Process swap usage via `/proc/[pid]/status`

**Dependencies:** ARG-001, ARG-005  
**Complexity:** M  
**Definition of Done:**
- [ ] Collector gathers swap I/O metrics
- [ ] Thrashing threshold configurable (default: >10MB/s in+out)
- [ ] Root cause process identified when possible
- [ ] Alert includes recommendations
- [ ] Problem logged with full diagnostic data

---

### Phase 3: Intelligence & Visibility

#### ARG-008: Implement Pattern Detection
**Description:** Analyze problem registry to detect recurring patterns and create proactive beads.

**Patterns to detect:**
- Same service restarted 3+ times per day
- Disk usage trending toward full (predictive)
- Memory usage creeping up (potential leak)
- Time-correlated issues (e.g., every day at 3am)

**Dependencies:** ARG-001, ARG-002  
**Complexity:** L  
**Definition of Done:**
- [ ] Pattern analyzer script reads `problems.jsonl`
- [ ] Runs daily (separate from 5-minute cycle)
- [ ] Creates summary bead with pattern analysis
- [ ] Includes recommendation for each pattern
- [ ] Historical window configurable (default: 7 days)

---

#### ARG-009: Add Historical Metrics Export
**Description:** Export problem statistics in a format suitable for dashboarding or trend analysis.

**Dependencies:** ARG-001, ARG-008  
**Complexity:** S  
**Definition of Done:**
- [ ] `argus-stats` command generates summary JSON
- [ ] Includes: problem counts by type, severity, action success rate
- [ ] Time-bucketed data (hourly, daily)
- [ ] Output works with common dashboard tools

---

#### ARG-010: Optional Relay Integration
**Description:** When Relay is available, send daily health summaries through it. Graceful no-op if Relay is down.

**Dependencies:** ARG-008, ARG-009  
**Complexity:** S  
**Definition of Done:**
- [ ] Health summary format defined
- [ ] Relay endpoint configurable
- [ ] Timeout + fallback to direct Telegram
- [ ] No Argus degradation if Relay unavailable
- [ ] Summary includes link to problems if dashboard exists

---

## 5. Recommended First Three Tasks

### Immediate Priority Queue

| Rank | Task | Rationale |
|------|------|-----------|
| 1 | **ARG-001: Problem Registry** | Foundation for all other features. Small scope, high leverage. Enables bead creation, dedup, and pattern analysis. |
| 2 | **ARG-003: Deduplication** | Prevents alert spam immediately. Quick win that improves UX today. Blocks ARG-002 from creating duplicate beads. |
| 3 | **ARG-002: Bead Creation** | Closes the loop between detection and task tracking. Critical for the ops autopilot vision. |

### Dispatch Instructions

**ARG-001 Dispatch Prompt:**
```
Implement Argus problem registry. Location: /home/chrote/athena/tools/argus

1. Create state directory: ~/argus/state/
2. Add log_problem() function to actions.sh that appends JSONL to state/problems.jsonl
3. Update argus.sh to call log_problem() before every action
4. Update deterministic orphan kill path to also log
5. Document schema in README.md
6. Test with: ./argus.sh --once && cat ~/argus/state/problems.jsonl | jq

Schema: {ts, severity, type, description, action_taken, action_result, bead_id, host}
Severity values: critical, warning, info
Type values: disk, memory, service, process, swap

Preserve existing behavior. Only add logging.
```

**ARG-003 Dispatch Prompt:**
```
Implement alert deduplication for Argus. Location: /home/chrote/athena/tools/argus

1. Add state/dedup.json to track recent problem keys
2. Problem key = "${type}:$(echo "$description" | sha256sum | cut -c1-16)"
3. Before alerting, check if key was seen within DEDUP_WINDOW (default 3600 seconds)
4. If duplicate, log with action_result="suppressed" but don't alert
5. Clean old entries from dedup.json (older than 24h)
6. Add DEDUP_WINDOW to argus.env.example

Test: trigger same alert twice within 1 minute, verify second is suppressed.
```

**ARG-002 Dispatch Prompt:**
```
Implement bead creation for Argus. Location: /home/chrote/athena/tools/argus

1. Add create_bead() to actions.sh
2. Call bd create --title "[argus] $type: $desc" --body "$diagnostics"
3. Capture bead ID and store in problem record (bead_id field)
4. Before creating, check if open bead exists for same problem key (dedup)
5. Trigger bead creation when:
   - action_result = "failure"
   - Same problem seen 3+ times in state/problems.jsonl within 24h
6. Gracefully skip if bd command not available

Test: simulate failed restart, verify bead created with proper tags.
```

---

## Appendix: Dependency Graph

```
ARG-001 (Registry)
    │
    ├──> ARG-003 (Dedup)
    │        │
    │        └──> ARG-002 (Beads)
    │                 │
    │                 ├──> ARG-006 (Restart Backoff)
    │                 └──> ARG-008 (Pattern Detection)
    │                          │
    │                          ├──> ARG-009 (Stats Export)
    │                          └──> ARG-010 (Relay Integration)
    │
    ├──> ARG-004 (Disk Cleanup)
    ├──> ARG-005 (Memory Hog ID)
    └──> ARG-007 (Swap Detection)
```

---

## Revision History

| Date | Change |
|------|--------|
| 2026-02-19 | Initial roadmap created |
