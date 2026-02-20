# Real Bugs — Needs Beads + Fix

These findings represent genuine issues that should be fixed.

## Error Handling Issues

### silent-fallback.ignored-error (ERROR)
Discarded error return values. Must be handled or explicitly justified.

- `ludus-magnus/internal/export/agent.go:128` — 	payload, _ := json.Marshal(value)
- `relay/internal/cli/cli.go:65` — 		home, _ := os.UserHomeDir()
- `relay/internal/cli/cli.go:79` — 		agent, _ = os.Hostname()
- `relay/internal/cli/cli.go:370` — 				ts, _ := time.Parse(time.RFC3339, m.TS)
- `relay/internal/cli/cli.go:400` — 	agents, _ := c.store.ListAgents()
- `relay/internal/cli/cli.go:401` — 	reservations, _ := c.store.ListReservations()
- `relay/internal/cli/cli.go:402` — 	commands, _ := c.store.ListCommands()
- `relay/internal/cli/cli.go:413` — 			meta, _ := c.store.ReadMeta(name)
- `relay/internal/cli/cli.go:437` — 		meta, _ := c.store.ReadMeta(name)
- `relay/internal/cli/cli.go:458` — 		expires, _ := time.Parse(time.RFC3339, r.ExpiresAt)
- `relay/internal/cli/cli.go:491` — 			ts, _ := time.Parse(time.RFC3339, cmd.TS)
- `relay/internal/cli/cli.go:550` — 		repo, _ = os.Getwd()
- `relay/internal/cli/cli.go:552` — 	repo, _ = filepath.Abs(repo)
- `relay/internal/cli/cli.go:648` — 		repo, _ = os.Getwd()
- `relay/internal/cli/cli.go:650` — 	repo, _ = filepath.Abs(repo)
- `relay/internal/cli/cli.go:672` — 		repoFilter, _ = filepath.Abs(repoFilter)
- `relay/internal/cli/cli.go:686` — 		expires, _ := time.Parse(time.RFC3339, r.ExpiresAt)
- `relay/internal/cli/cli.go:706` — 		expires, _ := time.Parse(time.RFC3339, r.ExpiresAt)
- `relay/internal/cli/cli.go:851` — 		reservations, _ := c.store.ListReservations()
- `relay/internal/cli/cli.go:855` — 			expires, _ := time.Parse(time.RFC3339, r.ExpiresAt)
- `relay/internal/store/store.go:162` — 		offset, _ = d.readCursor(agent)
- `relay/internal/store/store.go:573` — 	_, _ = f.Write([]byte(time.Now().UTC().Format(time.RFC3339) + "\n"))
- `relay/internal/store/store.go:631` — 	cmds, _ := d.ListCommands()
- `relay/internal/store/store.go:645` — 		agents, _ := d.ListAgents()
- `relay/internal/store/store.go:718` — 	reservations, _ := d.ListReservations()
- `relay/internal/store/store.go:731` — 	cmds, _ := d.ListCommands()

### error-context.nil-on-error (ERROR)
Returning nil instead of the error on error paths.

- `relay/internal/store/store.go:98` — 			return nil, nil
- `relay/internal/store/store.go:155` — 			return nil, nil
- `relay/internal/store/store.go:422` — 			return nil, nil
- `relay/internal/store/store.go:584` — 			return nil, nil

### error-context.swallowed-error (WARNING → treat as bug)
Errors caught but not propagated or logged.

- `argus/cmd/argus/main.go:33` — 	if err != nil {
- `argus/cmd/argus/main.go:87` — 		if err := srv.Shutdown(shutdownCtx); err != nil {
- `argus/internal/watchdog/watchdog.go:163` — 	if err := w.writeBreadcrumb(); err != nil {
- `argus/internal/watchdog/watchdog.go:177` — 		if err != nil {
- `argus/internal/watchdog/watchdog.go:208` — 	if err := w.writeBreadcrumb(); err != nil {
- `argus/internal/watchdog/watchdog.go:231` — 	if err := json.NewEncoder(rw).Encode(payload); err != nil {
- `ludus-magnus/internal/truthsayer/truthsayer.go:70` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:123` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:206` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:214` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:242` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:302` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:557` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/main.go:588` — 	if err != nil {
- `oathkeeper/cmd/oathkeeper/serve.go:100` — 			if err := webhook.NotifyUnbacked(beadID, meta.Message, meta.Category); err !=
- `oathkeeper/cmd/oathkeeper/serve.go:104` — 		if err := relayPublisher.NotifyUnbackedWithContext(beadID, meta.Message, meta.
- `oathkeeper/cmd/oathkeeper/serve.go:117` — 			if err := resolutionWebhook.NotifyResolved(beadID, evidence); err != nil {
- `oathkeeper/cmd/oathkeeper/serve.go:121` — 		if err := relayPublisher.NotifyResolved(beadID, evidence); err != nil {
- `oathkeeper/cmd/oathkeeper/serve.go:179` — 	if err := d.Run(); err != nil {
- `oathkeeper/pkg/beads/beads.go:336` — 	if err := json.Unmarshal(trimmed, &list); err != nil {
- `oathkeeper/pkg/recheck/recheck.go:111` — 			if err := r.config.UpdateFunc(UpdateRequest{
- `oathkeeper/pkg/recheck/recheck.go:123` — 		if err != nil {
- `oathkeeper/pkg/recheck/recheck.go:131` — 			if err := r.config.UpdateFunc(UpdateRequest{
- `oathkeeper/pkg/recheck/recheck.go:151` — 			} else if err := r.config.AlertFunc(c); err != nil {
- `oathkeeper/pkg/recheck/recheck.go:159` — 		if err := r.config.UpdateFunc(UpdateRequest{
- `relay/internal/cli/cli.go:518` — 			if err != nil {
- `relay/internal/cli/cli.go:600` — 	if err := c.store.Reserve(res); err != nil {
- `truthsayer/internal/cli/doctor.go:55` — 	if err != nil {
- `truthsayer/internal/cli/judge.go:183` — 				if err != nil {
