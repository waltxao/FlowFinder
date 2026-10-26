# Settings Wiring Audit — <App / Version>

> Date: <date> · Mode: read-only · Build: <version/build> · Platform: <platform>

## Scope

- Settings surfaces: <surfaces>
- Storage mechanisms: <defaults/config/database>
- Modules and targets: <targets>
- Out of scope: <surfaces or modules not audited>

## Verdict summary

| Verdict | Count | Highest-risk items |
|---|---:|---|
| `WIRED_VERIFIED` | 0 | |
| `WIRED_STATIC` | 0 | |
| `ORPHAN_WRITE` | 0 | |
| `PARTIAL` | 0 | |
| `BRIDGE_UNUSED_NATIVE_OK` | 0 | |
| `FEATURE_DEAD` | 0 | |
| `INCONCLUSIVE` | 0 | |

## Control matrix

| Control | Key forms | Default | Production reader | Indirect path | Reachability | Behavior evidence | Verdict | Next action |
|---|---|---|---|---|---|---|---|---|
| <control> | <constant + literal + variants> | <default> | `<file>:<line>` | `<file>:<line>` chain | reachable / blocked | test or probe | `<verdict>` | <action> |

## Evidence by control

### <Control>

- Control and write path: `<file>:<line>`
- Key forms searched: `<forms>`
- Production reader: `<file>:<line>` or none found
- Indirect path: `<write> -> <propagation> -> <consumer> -> <effect>`
- Reachability: reachable / blocked / unknown
- Behavior check: `<command or probe>`, `<result>`
- Verdict: `<verdict>`
- Unknowns and next action: <unknown or action>

## Coverage

- Search roots and targets: <roots>
- Key forms and patterns: <patterns>
- Excluded paths and reasons: <exclusions>
- Dynamic or generated surfaces not searched: <surfaces>
- Tests or probes run: <commands and results>
- Overall confidence: <summary>

## Recommended remediation

1. <highest-risk wiring fix or product decision>
2. <next fix>
3. <verification still required>
