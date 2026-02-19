# Athena Web — Implementation Roadmap

_Generated: 2026-02-19 by Opus Strategist_

---

## 1. Current State Summary

**Location:** `/home/chrote/athena/services/athena-web`  
**Status:** Functional but unstable — crashes under load

### What Exists

| Component | Status | Notes |
|-----------|--------|-------|
| **Express Server** | ✅ Implemented | Node.js 24.x, Express 5.x, port 9000 |
| **Frontend SPA** | ✅ Implemented | Vanilla JS, hash-based routing, 7 pages |
| **SSE Real-time** | ✅ Implemented | `routes/stream.js` + `services/sse-service.js` |
| **Test Suite** | ✅ Comprehensive | 4,644 lines across 37 test files |
| **Systemd Service** | ✅ Configured | Security-hardened unit file |
| **PWA Support** | ⚠️ Partial | manifest.json, sw.js shell, but not offline-capable |

### Existing Pages

| Page | Route | Function |
|------|-------|----------|
| **Oracle** | `#/oracle` | Dashboard: stats, activity feed, Ralph progress |
| **Beads** | `#/beads` | List view with filtering by status/priority |
| **Agents** | `#/agents` | Active agents, tmux pane output |
| **Artifacts** | `#/artifacts` | File browser for workspace artifacts |
| **Inbox** | `#/inbox` | Text/file submission interface |
| **Portal** | `#/portal` | Document browser and search |
| **Chronicle** | `#/chronicle` | Run history viewer |

### Existing API Routes

- `GET /api/status` — Aggregated status (beads, agents, runs, ralph)
- `GET /api/beads` — Bead listing with filters
- `GET /api/agents` — Agent listing with output capture
- `GET /api/runs` — Run history with filters
- `GET /api/docs/:path` — Document content
- `GET /api/artifacts` — Artifact file listing
- `POST /api/inbox/*` — Inbox submission endpoints
- `GET /api/stream` — SSE event stream

### Known Issues (from IMPROVEMENTS.md)

1. **Performance:** Status endpoint spawns 4+ subprocesses per request (beads CLI, tmux capture)
2. **No Caching:** Every request re-fetches from filesystem/CLI
3. **No Auth:** Anyone on network can kill agents, write documents
4. **Memory Pressure:** No subprocess pooling, potential leaks under sustained polling
5. **PWA Incomplete:** Offline fallback exists but data isn't cached

---

## 2. Target State Summary

From PRD, the target state is:

### Required Views

| View | Purpose | PRD Description |
|------|---------|-----------------|
| **Tapestry** | Visual bead overview | "All beads, colored by status, sized by priority" |
| **Timeline** | Run history | "Recent runs, outcomes, durations" |
| **Agents** | Agent monitoring | "Who's active, what they're working on" |
| **Health** | System metrics | "System metrics, service status" |

### Non-Functional Requirements

| Requirement | Description |
|-------------|-------------|
| **Stability** | Service doesn't crash under normal load |
| **Real-time** | WebSocket/SSE for live updates |
| **Mobile-responsive** | Works on phone for quick checks |
| **Reliable systemd** | Service survives restarts, auto-recovers |

### Definition of Done (from PRD)

1. ✅ Basic service exists
2. ⬜ Service stability (doesn't crash)
3. ⬜ Tapestry view implemented
4. ⬜ Timeline view implemented  
5. ⬜ Real-time updates (robust)
6. ⬜ Mobile-responsive
7. ⬜ Systemd service reliable

---

## 3. Gap Analysis

### 3.1 Views Gap

| PRD View | Current State | Gap |
|----------|---------------|-----|
| **Tapestry** | Beads page shows list, no visualization | Need: Canvas/SVG visualization with status colors, priority sizing |
| **Timeline** | Chronicle page shows runs | Enhance: Add duration bars, outcome visualization, better filtering |
| **Agents** | Exists and functional | Minor: Polish output streaming |
| **Health** | Oracle shows basic stats | Add: Memory usage, service uptime, subprocess counts |

### 3.2 Stability Gap

| Problem | Impact | Solution |
|---------|--------|----------|
| Subprocess spawning on every request | CPU/memory pressure, crashes | Add TTL cache layer (IMPROVEMENTS.md #1) |
| No request deduplication | Redundant CLI calls | Cache service with invalidation |
| Memory not monitored at runtime | Silent OOM | Add `/api/health/detailed` with process metrics |
| No graceful shutdown | Orphaned streams | Implement SIGTERM handler |

### 3.3 Mobile/Responsive Gap

| Current | Required |
|---------|----------|
| 10 media queries across CSS | Full responsive system |
| Bottom nav exists | Touch-optimized interactions |
| Some mobile meta tags | Complete PWA experience |

Analysis: Base mobile support exists but needs systematic responsive audit.

### 3.4 Real-time Gap

| Current | Gap |
|---------|-----|
| SSE implemented | Works, but agent output requires polling |
| Beads broadcast on change | No output streaming per-agent |
| Activity feed via SSE | Robust, needs edge-case testing |

---

## 4. Implementation Roadmap

### Phase 1: Stability Foundation (Critical)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **AW-001** | Implement Cache Service | Create `services/cache-service.js` with TTL-based caching. Wrap `listBeads()`, `listAgents()`, `listRuns()` with 3-5 second TTL. Invalidate on SSE filesystem events. | None | M | Cache hit rate >80% on repeated status calls. `npm test` passes. |
| **AW-002** | Parallel Status Aggregation | Refactor `routes/status.js` to use `Promise.allSettled()` for all 4 data sources. Add timing headers for debugging. | AW-001 | S | Status endpoint <50ms on cache hit. No sequential awaits in code. |
| **AW-003** | Graceful Shutdown Handler | Add SIGTERM/SIGINT handlers in `server.js`. Close SSE connections gracefully. Clear any intervals/timers. | None | S | `systemctl restart athena-web` completes in <2s. No orphaned connections. |
| **AW-004** | Health Endpoint Enhancement | Add `/api/health/detailed` returning: memory usage, uptime, active SSE connections, cache stats. | AW-001 | S | Endpoint returns valid metrics. Memory usage visible. |
| **AW-005** | Stability Test Suite | Add load test script (`scripts/load-test.js`) that hammers status endpoint. Run for 10 minutes, verify no memory growth >50MB. | AW-001, AW-002, AW-003 | M | Load test passes without OOM or crash. |

### Phase 2: Core Views (PRD Requirements)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **AW-010** | Tapestry View - Data Model | Design bead-to-visual mapping: status→color (gold=open, blue=active, green=done, red=blocked), priority→size. Add `/api/beads/tapestry` endpoint returning positioned data. | None | S | Endpoint returns beads with x/y coordinates, color, size. Tests pass. |
| **AW-011** | Tapestry View - Canvas Renderer | Create `public/js/pages/tapestry.js` with Canvas/SVG rendering. Beads as circles, connected by dependency lines. Pan/zoom support. | AW-010 | L | Renders 50+ beads smoothly. Click selects bead. Zoom works on mobile. |
| **AW-012** | Tapestry View - Live Updates | Connect Tapestry to SSE stream. Animate bead status transitions (color morphs). New beads fade in. | AW-010, AW-011 | M | Bead status change reflects in <1s. Animation is smooth (60fps). |
| **AW-013** | Timeline View Enhancement | Enhance Chronicle page: add horizontal timeline visualization, duration bars, color-coded outcomes. Add time-range filter (24h, 7d, 30d). | None | M | Timeline shows runs as bars. Duration visible. Filter works. |
| **AW-014** | Health Dashboard Panel | Add Health section to Oracle page: service uptime, memory trend (sparkline), cache hit rate, active connections. Pull from AW-004 endpoint. | AW-004 | M | Oracle shows system health. Updates via SSE. |

### Phase 3: Mobile & Polish

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **AW-020** | Responsive Audit & Fix | Audit all pages at 375px, 768px, 1024px. Fix overflow issues, touch targets <44px, unreadable text. Add CSS custom properties for breakpoints. | None | M | All pages usable at 375px. No horizontal scroll. Touch targets ≥44px. |
| **AW-021** | Tapestry Mobile Adaptation | Add touch gestures for pan/zoom on Tapestry. Simplify detail view for small screens. | AW-011, AW-020 | M | Tapestry usable on iPhone SE. Pinch-zoom works. |
| **AW-022** | PWA Offline Caching | Enhance `sw.js` with stale-while-revalidate for API endpoints. Pre-cache all static assets. Add offline banner component. | None | M | Dashboard shows cached data offline. Lighthouse PWA ≥90. |
| **AW-023** | Agent Output Streaming | Add `GET /api/agents/:name/stream` SSE endpoint. Replace polling in agents page with EventSource. | None | M | Agent output updates in real-time. No polling intervals in client. |

### Phase 4: Hardening (Production-Ready)

| ID | Title | Description | Dependencies | Complexity | Definition of Done |
|----|-------|-------------|--------------|------------|-------------------|
| **AW-030** | Authentication Middleware | Add Bearer token auth for mutating endpoints (POST, PUT, DELETE). Read-only remains open. Add login UI. | None | M | Unauthorized POST returns 401. Token auth works. |
| **AW-031** | Activity Persistence | Add SQLite activity log (`better-sqlite3`). Write events on SSE broadcasts. Add `/api/activity` endpoint with pagination. | None | L | Activity survives restart. Pagination works. |
| **AW-032** | Error Boundary & Recovery | Add global error boundary in frontend. Auto-reconnect SSE on disconnect. Toast notifications for errors. | None | S | SSE reconnects automatically. Errors show user-friendly message. |
| **AW-033** | Documentation Update | Update README with all new features. Add API documentation. Update PRD with completed items. | All prior | S | README accurate. API docs exist. PRD checkboxes updated. |

---

## 5. Recommended First Three Tasks

### 1. **AW-001: Implement Cache Service** (Start Here)

**Rationale:** This is the root cause of instability. Every status poll spawns multiple subprocesses. With SSE clients polling, this quickly overwhelms the system.

**Agent Prompt:**
```
Create a cache service at services/cache-service.js for Athena Web.

Requirements:
1. Simple TTL cache using Map + timestamps (no dependencies)
2. Methods: get(key), set(key, value, ttlMs), invalidate(key), clear()
3. Auto-cleanup of expired entries on get()

Then wrap these service calls with caching:
- services/beads-service.js:listBeads() - 3 second TTL
- services/tmux-service.js:listAgents() - 5 second TTL  
- services/runs-service.js:listRuns() - 5 second TTL

Add cache invalidation call in services/sse-service.js when filesystem changes detected.

Tests: Add tests/services/cache-service.test.js with full coverage.
Run: npm test to verify nothing breaks.
```

**Complexity:** M  
**Estimated Time:** 2-3 hours

---

### 2. **AW-002: Parallel Status Aggregation** (Quick Win)

**Rationale:** Even with caching, the sequential await pattern in status.js adds latency. This is a surgical fix.

**Agent Prompt:**
```
Refactor routes/status.js to fetch all data sources in parallel.

Current code likely has sequential awaits:
  const beads = await listBeads();
  const agents = await listAgents();
  const runs = await runsService.listRuns();
  const ralph = await ralphService.getRalphStatus();

Change to:
  const [beadsResult, agentsResult, runsResult, ralphResult] = 
    await Promise.allSettled([
      listBeads(),
      listAgents(),
      runsService.listRuns(),
      ralphService.getRalphStatus()
    ]);

Handle rejected promises gracefully (return partial data, not 500).
Add X-Response-Time header for observability.

Run: npm test
Verify: curl -w "%{time_total}" http://localhost:9000/api/status
```

**Complexity:** S  
**Estimated Time:** 1 hour

---

### 3. **AW-010: Tapestry View - Data Model** (Feature Start)

**Rationale:** The Tapestry is the signature PRD feature. Starting with the data model lets a subsequent agent build the UI.

**Agent Prompt:**
```
Add Tapestry data endpoint at GET /api/beads/tapestry in routes/beads.js.

The endpoint should:
1. Fetch all beads via listBeads()
2. Transform each bead to tapestry format:
   {
     id: bead.id,
     title: bead.title,
     status: bead.status,
     priority: bead.priority,
     color: statusToColor(status),  // gold=open, blue=active, green=done, red=blocked
     size: priorityToSize(priority), // 1→40px, 2→32px, 3→24px, 4→20px
     x: computed,  // Use force-directed or grid layout algorithm
     y: computed,
     dependencies: bead.dependencies || []
   }
3. Layout algorithm: Simple grid for now (can enhance later)
   - 6 columns, row = Math.floor(index / 6), col = index % 6
   - x = col * 120 + 60, y = row * 100 + 60

Add tests at tests/routes/beads-tapestry.test.js.
Run: npm test
```

**Complexity:** S  
**Estimated Time:** 1-2 hours

---

## Appendix: Task Dependency Graph

```
Phase 1 (Stability):
AW-001 ─┬─► AW-002 ─┬─► AW-005
        │           │
        └─► AW-004 ─┘
            
AW-003 (independent)

Phase 2 (Views):
AW-010 ──► AW-011 ──► AW-012
AW-004 ──► AW-014
AW-013 (independent)

Phase 3 (Mobile):
AW-020 ──► AW-021
AW-011 ──► AW-021
AW-022, AW-023 (independent)

Phase 4 (Hardening):
All prior ──► AW-033
AW-030, AW-031, AW-032 (independent)
```

---

## Notes for Dispatching

1. **Each task is self-contained** — can be dispatched to a coding agent with the prompt provided
2. **Tests are mandatory** — every task includes test requirements
3. **Phase 1 is blocking** — don't start Phase 2 until stability is confirmed
4. **AW-011 is the largest task** — consider splitting into Canvas setup + interactivity
5. **Verify with load test** (AW-005) before declaring Phase 1 complete

---

_"The Loom Room awaits its weaving."_
