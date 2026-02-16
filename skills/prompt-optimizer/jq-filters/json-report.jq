# .[0] is metrics array, .[1] is recommendations array
# Both are arrays of template objects
(.[0]) as $metrics_arr |
(.[1]) as $recs_arr |
{
  generated_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
  analyzed_runs: ($metrics_arr | map(.total_runs) | add // 0),
  templates: ($metrics_arr | map(
    . as $m |
    ($recs_arr | map(select(.template == $m.template))[0]) as $rec |
    {
      name: $m.template,
      metrics: {
        total_runs: $m.total_runs,
        success_rate: (if $m.total_runs > 0 then ($m.successful / $m.total_runs) else 0 end),
        failure_rate: (if $m.total_runs > 0 then ($m.failed / $m.total_runs) else 0 end),
        retry_rate: (if $m.total_runs > 0 then ($m.retries / $m.total_runs) else 0 end),
        avg_duration_seconds: (if ($m.durations | length > 0) then ($m.durations | add / length) else null end),
        max_duration_seconds: (if ($m.durations | length > 0) then ($m.durations | max) else null end),
        failure_reasons: $m.failure_reasons
      },
      issues: ($rec.issues // []),
      bead_ids: $m.bead_ids
    }
  ))
}
