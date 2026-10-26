# Search Playbook

Use this reference when building the key matrix, classifying hits, or investigating a suspect bridge or feature.

## 1. Key-form matrix

Never search only a symbol name. Build every form before judging the key.

| Form | Example | Why it matters |
|---|---|---|
| Constant symbol | `FFUserDefaultsKeys.startupLocation` | Finds direct constant references only |
| Persisted literal | `"startup_location"` | Production code often bypasses constants |
| camelCase | `startupLocation` | JSON, JavaScript, or DTO field |
| snake_case | `startup_location` | UserDefaults, plist, or database column |
| kebab-case | `startup-location` | CLI flag or web storage key |
| dotted path | `app.startup.location` | Nested configuration object |
| Environment variable | `APP_STARTUP_LOCATION` | Service or launcher override |
| Migration or fallback key | `old_startup_location` | Legacy path that may still control behavior |

Record the exact forms used in the report. Search with fixed strings first, then use a regex only when the storage format requires variants.

## 2. Search scope

Search:

- every app target, extension, helper, agent, plugin, and share target;
- bridge and FFI layers in both directions;
- app startup, window restoration, background jobs, schedulers, and menu actions;
- generated code and configuration loaders;
- scripts that may write defaults or config;
- tests, fixtures, previews, and documentation as evidence only.

Do not count build products, dependency caches, or vendored code as production consumers. List exclusions explicitly.

Search all languages that can read the same storage. A Swift app may expose a key that is read by a Rust bridge, an Electron preload script, or a helper process.

## 3. Storage and read APIs

| Stack | Common write and read APIs | Additional places to search |
|---|---|---|
| Swift/AppKit | `UserDefaults.standard`, `UserDefaults(suiteName:)`, `@AppStorage`, `NSUserDefaultsController` | app launch, window restoration, KVO, Combine, notifications, bindings |
| Objective-C/Cocoa | `NSUserDefaults`, `NSUserDefaultsController`, `bindings` | KVO observers, nib bindings, defaults registration |
| Electron/Web | `localStorage`, `sessionStorage`, `electron-store`, config files | preload scripts, IPC handlers, config service, React context |
| Cross-platform desktop | settings service, JSON/TOML/YAML/plist loaders | startup bootstrap, plugin API, migrations |
| CLI/server | environment variables, CLI flags, config files, database | entrypoint, config reload, feature flags |
| Rust/C++ bridge | FFI exports, structs, callback tables, registration maps | wrapper layer, dynamic lookup, task scheduler, event loop |

Find the write site and the storage default separately. A default registration is not a production reader.

## 4. Classify every hit

| Hit type | Counts as consumer? | Notes |
|---|---|---|
| Production service, policy, view model, command | Yes | Follow the value to an observable effect |
| Settings UI rendering the stored value | No | UI-only readback |
| Default registration or migration write | No | Setup or history, not behavior |
| Test, fixture, preview, demo | No | Evidence of intent or coverage only |
| Documentation, comment, changelog | No | Not executable |
| Logging or telemetry | Usually no | Count only if it drives a behavior or user-visible state |
| Analytics or crash reporting | Usually no | Does not prove the setting changes the product |

Classify "read into a variable but never used" as a partial path, not a consumer.

## 5. Indirect propagation patterns

Trace at least these patterns when a direct reader is missing:

- write → notification or KVO → observer → service or policy;
- write → Combine publisher → view model → UI or command;
- write → computed getter → sort/filter/format decision;
- write → dependency-injected service → background job;
- write → app launch or window restoration → initial state;
- write → config reload → subsystem or plugin;
- write → scheduler or task aggregator → user-visible task;
- write → bridge → native implementation → observable effect.

Write one chain per consumer:

`<write site> -> <propagation> -> <consumer> -> <observable effect>`

If any hop is inferred rather than verified, label it.

## 6. Bridge and FFI liveness

An unused bridge symbol is not a feature verdict. Check in this order:

1. Direct wrappers and generated bindings for the symbol.
2. Alternate native or service-layer implementations.
3. Producers and aggregators: task center, scheduler, event bus, job runner, plugin registry.
4. Callback tables, registration maps, dynamic lookup, reflection, or dependency injection.
5. User actions that should reach the feature, and the code path from those actions.
6. Runtime evidence that the feature is reachable.

Observed regression case: a generic task-submit FFI had no Swift caller, which initially suggested the task center was an empty shell. The task center actually aggregated copy, move, duplicate-scan, and batch-rename tasks from a Swift service. The correct verdict was "unused bridge, feature live", not "dead feature".

Record `BRIDGE_UNUSED_NATIVE_OK` when an alternate path exists. Reserve `FEATURE_DEAD` for a feature-level conclusion after producers, consumers, and runtime reachability have all been checked.

## 7. Behavior verification

Prefer, in order:

1. An existing test that toggles the setting and asserts an observable result.
2. A test run in an isolated suite or temporary config directory.
3. A minimal runtime probe comparing default and toggled states.
4. Static chain evidence with an explicit "not runtime verified" label.

For each run, capture:

- command and environment;
- app version/build and target;
- before and after state;
- whether persistence or relaunch was required;
- cleanup and restoration result.

Use an isolated defaults suite such as a temporary suite name, or a temporary config directory. Do not mutate the user's production preferences. If a test writes to `UserDefaults.standard`, verify that it restores state or avoid running it against a live profile.

## 8. Evidence tiers

| Tier | Evidence | Allowed verdict |
|---|---|---|
| E3 | Runtime observed effect | `WIRED_VERIFIED` |
| E2 | Complete static chain from writer to reachable consumer | `WIRED_STATIC` |
| E1 | Reader or indirect path exists, but reachability or effect is unproven | `PARTIAL` or `INCONCLUSIVE` |
| E0 | Name or string match only | No wiring verdict |

Never upgrade E0 or E1 to E3 because tests exist, a getter looks correct, or documentation says the setting works.

## 9. Coverage appendix

Include:

- key forms and exact search patterns;
- roots, targets, modules, and generated surfaces searched;
- excluded directories and reasons;
- dynamic surfaces not searchable statically;
- commands, tests, and probes run;
- result counts by verdict;
- highest-risk gaps and the evidence still needed.

A missing-reader verdict is invalid without a coverage statement.

## 10. Search command patterns

Use repository-appropriate tools, but keep the key forms explicit:

```bash
rg -n --hidden --glob '!build/**' --glob '!node_modules/**' \
  --fixed-strings '<persisted-literal>' <root>

rg -n --hidden --glob '!build/**' --glob '!node_modules/**' \
  '<constant-symbol>|<camelCase>|<snake_case>' <root>
```

Read the matching lines and classify them. Do not infer wiring from match counts.
