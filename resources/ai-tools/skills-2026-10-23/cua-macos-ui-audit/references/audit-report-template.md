# macOS UI Audit Report Template

Use this template for a read-only macOS UI audit. Keep the coverage matrix, findings, blocked items, and evidence manifest separate. Do not use this template to claim full coverage when rows remain unverified.

## Metadata

```text
audit_date:
auditor:
app_source_path:
audit_copy_path:
bundle_id:
executable:
version:
pid:
screen_size:
default_window_geometry:
minimum_window_geometry:
appearance_modes_tested:
baseline_test_command:
baseline_result:
```

## Scope and Method

```text
requested_scope:
included_surfaces:
excluded_surfaces:
static_review:
baseline_tests:
live_audit:
isolation_method:
permission_events:
```

## Coverage Matrix

| ID | Surface / state | Entry path | Preconditions | Evidence | AX / behavior | Verdict | Notes |
|---|---|---|---|---|---|---|---|
| S-01 |  |  |  |  |  | Unverified |  |

Verdicts:

- `Verified` — current evidence covers the claimed surface and state.
- `Unverified` — not observed, or only partly observed.
- `Blocked` — environment or automation prevented a reliable check; include a row in the blocked table.
- `Not audited` — outside the acknowledged scope.

Every `Verified` row must have a current screenshot or AX/behavior evidence pointer. A report, issue ticket, or code path alone is not a verified UI row.

Coverage should include, where the app supports them:

- empty, populated, loading, error
- selected, focused, inactive
- menus, toolbar, tabs, sheets, popovers, dialogs
- light, dark, high contrast
- default size, declared minimum size, full screen
- mouse, keyboard, and Accessibility paths

## Findings

### F-01 — Short title

```text
severity:
surface:
classification: Confirmed | Suspected | Automation artifact | Blocked
reproduction:
expected:
actual:
evidence:
AX excerpt:
code reference:
isolation caveat:
```

Rules:

- Separate a product defect from an automation artifact.
- A transition, focus, menu-tracking, lock-screen, or permission-gate failure is not a product defect unless a clean second path confirms it.
- If live evidence is clear but code evidence is missing, keep `Confirmed` or `Suspected` and state what is missing.
- A confirmed defect may have an uncertain root cause; do not downgrade it merely because the cause is not yet known.

## Blocked Items

| ID | Surface | Attempts | Exact blocker | Observed state | Unblock action | Retest plan |
|---|---|---|---|---|---|---|
| B-01 |  |  |  |  |  |  |

A `Blocked` item must name the exact environmental or automation blocker. Do not use “automation failed” as a substitute for the error text, PID, window, and menu path that were observed.

## Evidence Manifest

| Captured at | Artifact | Type | Pixel size / length | PID / Bundle ID | Ownership assertion | Window geometry | Surface ID | What it proves |
|---|---|---|---|---|---|---|---|---|
|  |  | screenshot / AX / log / video |  |  | `OWNERSHIP=OK` / not asserted |  |  |  |

Checks before cleanup:

- Every artifact path exists.
- Each screenshot was opened and its dimensions verified.
- Each screenshot carries an `OWNERSHIP=OK` assertion for the audit copy's PID; a capture without one is not evidence for that PID.
- The manifest points to stable paths, not only `/tmp`.
- The report references only artifacts present in the manifest.
- Sensitive paths or file names are redacted before external sharing.

## Baseline Tests

```text
command:
executed_count:
passed_count:
failed_count:
failures:
known_flaky_or_environment_exclusions:
test_artifacts:
```

## Isolation and Permission Caveats

```text
new_bundle_id:
new_tcc_identity:
ad_hoc_signing:
shared_application_support:
sandbox_or_container_changes:
system_permission_prompts:
user_actions_required:
```

## Coverage Summary

Use this exact kind of summary; adjust the counts from the matrix:

```text
Coverage: X verified, Y blocked, Z unverified, W not audited.
This is not a full audit unless every coverage row has current evidence.
```

Do not write:

- “All UI passed” when any row is `Blocked`, `Unverified`, or `Not audited`.
- “Verified” for a surface that was only inspected in code.
- “Fixed” for a finding that has not been retested in the affected surface.

## Fix Gate

Before any product code change:

- [ ] The coverage matrix is complete for the acknowledged scope.
- [ ] The `Blocked` table explains every blocked row and its unblock action.
- [ ] The report states what is still unverified.
- [ ] The user has explicitly authorized the fix pass.

After a fix:

- [ ] Re-run the affected coverage rows.
- [ ] Re-run the baseline checks.
- [ ] Update the matrix verdicts and evidence manifest.
- [ ] Keep previous evidence rather than overwriting it.
