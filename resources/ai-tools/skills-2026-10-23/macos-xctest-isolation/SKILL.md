---
name: macos-xctest-isolation
description: "Prevent XCTest runs in macOS apps from polluting real UserDefaults. Use when a test host or unit test instantiates production window controllers or app state that persists preferences, when the next normal app launch restores /tmp or a test directory, when configuring Xcode TestAction CFFIXED_USER_HOME or FF_TESTING, or when verifying that defaults keys are unchanged before and after xcodebuild test."
---

# macOS XCTest Isolation

## Core Rule

Treat isolation as three independent layers. Each has failed alone in practice:

1. **Redirect the test home** with `CFFIXED_USER_HOME` in the scheme's `TestAction`.
2. **Guard writes at runtime** with an XCTest detection check at every user-level persistence site.
3. **Assert no change** by snapshotting affected defaults keys before and after the test command.

Passing tests are not evidence of isolation. Unchanged defaults are.

## When to Use

Use this skill when any of these appear:

- The next normal launch opens `/tmp/...`, a test home, or a directory the user never chose.
- Tests instantiate `MainWindowController`, `AppDelegate`, window controllers, or other production objects that save state.
- New code persists last opened paths, window frames, sidebar width, tab sessions, or view modes.
- An Xcode scheme gains or moves `CFFIXED_USER_HOME`, `FF_TESTING`, or similar test variables.
- `defaults read <bundle-id> <key>` shows a test path after `xcodebuild test`.
- A Makefile or CI job creates a test-home directory and assumes that isolates the host.

## Diagnosis

1. Read the polluted values directly:
   ```bash
   defaults read com.example.app last_left_path
   defaults read com.example.app last_right_path
   ```
2. Enumerate every write, not just the visible key. Search the codebase for:
   - `UserDefaults.standard.set`
   - `UserDefaults.standard.removeObject`
   - `UserDefaults(suiteName:`
   - `@AppStorage`
3. Inspect subscriptions that write during initialization. A `$state.sink { UserDefaults.standard.set(...) }` in a controller init runs in every test that creates that controller.
4. Inspect the scheme:
   - `TestAction` must contain `CFFIXED_USER_HOME` and a test flag.
   - `LaunchAction` must not contain the test home.
   - `shouldUseLaunchSchemeArgsEnv="YES"` copies LaunchAction arguments and environment into tests. Never use it to smuggle a test home out of LaunchAction.
5. Check build scripts. `mkdir -p /tmp/app-test-home/Desktop` creates directories but does not redirect `NSHomeDirectory()` or `UserDefaults`. The environment must actually reach the test host.

## Fix

### 1. TestAction Only

Put isolation variables on the test action:

```xml
<TestAction ... shouldUseLaunchSchemeArgsEnv = "YES">
  ...
  <EnvironmentVariables>
    <EnvironmentVariable key = "CFFIXED_USER_HOME"
                         value = "/tmp/app-test-home"
                         isEnabled = "YES"/>
    <EnvironmentVariable key = "FF_TESTING"
                         value = "1"
                         isEnabled = "YES"/>
  </EnvironmentVariables>
</TestAction>
```

Create `/tmp/app-test-home/Desktop` and `/tmp/app-test-home/Documents` before running tests. Remove `CFFIXED_USER_HOME` from `LaunchAction`; leaving it there makes normal runs use the test home.

If LaunchAction carries unrelated variables that tests need, consider `shouldUseLaunchSchemeArgsEnv="NO"` and declare the complete test environment in TestAction.

### 2. Runtime Detection

Scheme environment alone may not reach the app host. Detect XCTest in code:

```swift
static var isRunningTests: Bool {
    ProcessInfo.processInfo.environment["FF_TESTING"] == "1"
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}
```

At normal startup, `applicationDidFinishLaunching` runs before the XCTest bundle is injected. Do not rely on `NSClassFromString` there; use environment variables only:

```swift
let isRunningTests =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
```

### 3. Guard Persistence

Guard at the write site, not only when choosing the startup directory:

```swift
if !MainWindowController.isRunningTests {
    for (vm, key) in [(leftViewModel, lastLeftKey), (rightViewModel, lastRightKey)] {
        vm.$state.map(\.path).removeDuplicates().sink { path in
            guard !path.isEmpty else { return }
            UserDefaults.standard.set(path, forKey: key)
        }.store(in: &cancellables)
    }
}
```

Repeat for every user-level key: window frames, sidebar width, tab sessions, view modes, recent items. Do not guard unrelated per-test temporary state.

For tests that intentionally verify persistence, inject a dedicated `UserDefaults(suiteName:)` or a persistence protocol. Do not weaken the global guard.

### 4. Remove Existing Pollution

Delete only keys confirmed polluted. Back up first:

```bash
defaults export com.example.app /tmp/com.example.app.defaults.backup.plist
defaults delete com.example.app last_left_path
defaults delete com.example.app last_right_path
```

Never `defaults delete com.example.app` as a cleanup shortcut; that destroys the user's real preferences.

## Verification

Run the bundled script around the real test command:

```bash
scripts/assert-defaults-unchanged.sh \
  --domain com.example.app \
  --keys last_left_path,last_right_path \
  -- xcodebuild test -project App.xcodeproj -scheme AppTests \
     -destination 'platform=macOS'
```

It snapshots each key (missing keys become `__UNSET__`), runs the command, re-reads each key, prints before/after, and exits non-zero if any key was created, changed, or removed.

Complete the acceptance sequence:

1. Full test suite passes.
2. The script reports `PASS` and every checked key remains `<unset>` or unchanged.
3. Build and launch the app normally, without test environment:
   ```bash
   env -u CFFIXED_USER_HOME -u FF_TESTING open /path/to/App.app
   ```
4. Confirm the app opens the real user directory, not `/tmp`.
5. Re-read the keys after the normal launch; they must contain real user paths.

Add a detection test:

```swift
func testHostAppDetectsXCTestIsolation() {
    XCTAssertTrue(MainWindowController.isRunningTests)
}
```

That test proves detection, not write prevention. Keep the external before/after assertion as the real acceptance check.

## Pitfalls

- **Scheme env is not enough.** A TestAction variable can fail to reach the host; the run can still write real defaults.
- **LaunchAction leakage.** Moving `CFFIXED_USER_HOME` to LaunchAction makes the actual product run against the test home.
- **Directory creation is not isolation.** Creating the test home says nothing about which home the host resolves.
- **`NSClassFromString` timing.** It is unreliable before the test bundle loads; use environment variables during launch.
- **Single-key tunnel vision.** The visible key is rarely the only one. Enumerate every persistence write.
- **Over-blocking.** Tests that need persistence must use an injected suite; a global guard otherwise makes them silently stop testing storage.
- **`defaults` caching.** Read after the test or app process exits. Do not kill `cfprefsd` to force freshness.
- **Cleanup scope.** Delete named polluted keys, never the whole domain.

## Acceptance Checklist

- [ ] TestAction has `CFFIXED_USER_HOME` and a test flag.
- [ ] LaunchAction has no test home.
- [ ] Runtime detection uses environment plus XCTest class checks.
- [ ] Every user-level persistence site is guarded.
- [ ] Existing polluted keys are cleaned with a backup.
- [ ] `assert-defaults-unchanged.sh` passes around the full suite.
- [ ] A normal launch opens real user paths.
- [ ] A detection test exists and passes.
