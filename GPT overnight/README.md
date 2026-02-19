# GPT Overnight

This folder contains long-run system analysis artifacts and implementation plans.

## Layout

- `IMPLEMENTATION-PLAN.md` — cross-system improvement plan.
- `runs/<timestamp>/` — generated snapshots, logs, and final recommendations from overnight runs.

## Run Command

```bash
cd /home/perttu/athena
./scripts/gpt-overnight-run.sh --duration-seconds 10800 --interval-seconds 900
```

## Detatched Run (tmux)

```bash
tmux new-session -d -s gpt-overnight \
  "cd /home/perttu/athena && ./scripts/gpt-overnight-run.sh --duration-seconds 10800 --interval-seconds 900"
```

## Monitor

```bash
tmux ls | rg gpt-overnight
tail -f "/home/perttu/athena/GPT overnight/runs/<timestamp>/run.log"
```
