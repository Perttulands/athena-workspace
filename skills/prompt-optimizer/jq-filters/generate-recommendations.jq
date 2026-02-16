map(
  .template as $tpl |
  .issues |= map(
    . as $issue |
    . + {
      recommendations: (
        if .category == "high_retry_rate" then
          [
            {
              section: "Constraints",
              change_type: "add_constraint",
              suggestion: "Add explicit pre-work validation steps (e.g., \"Verify all {{VARIABLES}} are non-empty before proceeding\")",
              rationale: "Reduces blind exploration and wasted retries"
            },
            {
              section: "Context Files to Read",
              change_type: "clarify",
              suggestion: "Add fallback discovery step if context files list is empty",
              rationale: "Ensures agent always has starting context"
            }
          ]
        elif .category == "high_failure_rate" then
          [
            {
              section: "Acceptance Criteria",
              change_type: "add_checklist",
              suggestion: "Add explicit verification checklist with pass/fail criteria",
              rationale: "Prevents premature completion claims"
            },
            {
              section: "Constraints",
              change_type: "add_constraint",
              suggestion: "Add \"Do not report complete until all acceptance criteria are verifiably met\"",
              rationale: "Enforces quality gate before completion"
            }
          ]
        elif .category == "duration_outliers" then
          [
            {
              section: "Objective",
              change_type: "scope_boundary",
              suggestion: "Add explicit scope boundaries and time budget (e.g., \"This should take ~10 minutes. If approaching 20 minutes, report blocker.\")",
              rationale: "Prevents scope creep and unbounded exploration"
            },
            {
              section: "Constraints",
              change_type: "add_constraint",
              suggestion: "Add \"If task requires >30 minutes, break into sub-tasks and report back\"",
              rationale: "Enforces decomposition for large work"
            }
          ]
        elif .category == "recurring_failure" then
          [
            {
              section: "Error Handling",
              change_type: "add_section",
              suggestion: ("Add section: \"If you encounter: " + .description + ", do: [specific remediation]\""),
              rationale: "Provides explicit recovery path for known failure mode"
            }
          ]
        else
          []
        end
      )
    }
  )
)
