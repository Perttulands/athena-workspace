map(
  . as $m |
  {
    template: .template,
    total_runs: .total_runs,
    successful: .successful,
    retries: .retries,
    failed: .failed,
    durations: .durations,
    bead_ids: .bead_ids,
    issues: (
      [] +
      (if (.retries > 0 and (.retries / .total_runs) > 0.3) then
        [{
          severity: "major",
          category: "high_retry_rate",
          description: ("High retry rate (" + ((.retries / .total_runs * 100) | floor | tostring) + "%) indicates unclear instructions or missing context"),
          evidence: .bead_ids[:3]
        }]
      else [] end) +
      (if (.failed > 0 and (.failed / .total_runs) > 0.4) then
        [{
          severity: "critical",
          category: "high_failure_rate",
          description: ("High failure rate (" + ((.failed / .total_runs * 100) | floor | tostring) + "%) suggests fundamental template issues"),
          evidence: .bead_ids[:3]
        }]
      else [] end) +
      (if (.durations | length > 0) then
        ((.durations | add / length) as $avg |
         (.durations | max) as $max |
         if ($max > $avg * 2 and $max > 300) then
           [{
             severity: "major",
             category: "duration_outliers",
             description: ("Significant duration outliers (max: " + ($max | floor | tostring) + "s, avg: " + ($avg | floor | tostring) + "s) suggest scope creep or unclear boundaries"),
             evidence: []
           }]
         else [] end)
      else [] end) +
      (if (.failure_reasons | length > 0) then
        (.failure_reasons | map(
          if .count > 1 then
            {
              severity: "major",
              category: "recurring_failure",
              description: ("Recurring failure: " + .reason + " (occurred " + (.count | tostring) + " times)"),
              evidence: []
            }
          else null end
        ) | map(select(. != null)))
      else [] end)
    )
  }
)
