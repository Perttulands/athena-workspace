# Beads Integration

How each system component integrates with beads, the universal work tracking unit.

## dispatch.sh

Requires a bead ID to dispatch. Creates run and result records in `state/runs/` and `state/results/` linked to the bead. The bead ID is used as the tmux session name and file key.

## problem-detected.sh

Creates beads with a `[source]` prefix in the title for any detected problem. Logs to `state/problems.jsonl` with the bead ID. Wakes Athena for triage.

## Argus

Calls `problem-detected.sh` when observations repeat 3+ times. Beads are tagged with `[argus]` prefix.

## Truthsayer

Creates beads for scan errors when invoked with `--create-beads`. Beads are tagged with `[truthsayer]` prefix.

## Oathkeeper

Creates beads for unresolved agent commitments. Beads are tagged with `oathkeeper`.

## Debt Ceiling Cron

Counts open beads periodically. Alerts when the count exceeds the configured threshold, preventing unbounded work accumulation.

## verify.sh

Runs verification on completed agent work (lint, test, scan). Writes results to `state/results/{bead}-verify.json`. Verification outcome determines whether the bead can be closed.
