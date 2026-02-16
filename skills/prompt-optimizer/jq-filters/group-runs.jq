# Group by template_name if exists, otherwise use "custom"
group_by(if .template_name then .template_name else "custom" end) |
map(
  ((.[0].template_name // "custom")) as $tpl |
  {
    template: $tpl,
    total_runs: length,
    successful: ([.[] | select(.status == "completed" or .status == "success")] | length),
    failed: ([.[] | select(.status == "failed" or .status == "error")] | length),
    running: ([.[] | select(.status == "running")] | length),
    retries: ([.[] | select(.attempt > 1)] | length),
    durations: [.[] | select(.duration_seconds != null) | .duration_seconds],
    failure_reasons: ([.[] | select(.failure_reason != null) | .failure_reason] | group_by(.) | map({reason: .[0], count: length})),
    bead_ids: [.[] | .bead]
  }
)
