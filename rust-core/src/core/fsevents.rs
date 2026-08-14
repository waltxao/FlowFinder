//! macOS FSEvents watcher for directory change notifications.
//!
//! Provides a lightweight wrapper around the macOS FSEvents API
//! (`FSEventStreamCreate`) to notify the Swift UI when filesystem changes
//! occur. On non-macOS targets (Linux CI etc.) a minimal polling stub keeps
//! the module compilable and the `start`/`stop` lifecycle working.
//!
//! The FSEvents bindings are declared directly via `extern "C"` (same pattern
//! as `cow_copy::native` for `clonefile(2)`) so no extra crates or build
//! flags are required — FSEvents and CoreFoundation are part of the macOS SDK.

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use parking_lot::{Condvar, Mutex};

/// Return code for a failed watcher setup. Mapped to `FF_ERR_IO` by the
/// FFI layer (`ff_fsevents_start`).
pub const FSEVENTS_ERR: i32 = -1;

/// Upper bound for how long `start` waits for the worker's setup outcome.
/// Setup is a handful of CoreFoundation calls, so this is a generous safety
/// valve against a pathological hang rather than a real deadline.
const SETUP_TIMEOUT: Duration = Duration::from_secs(10);

/// Lifecycle status of the FSEvents watcher.
///
/// The status is process-global (there is at most one watcher) and is
/// updated at every lifecycle transition so the Swift side can distinguish a
/// running watcher from a failed start.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WatcherStatus {
    /// No watcher is running (initial state, or after `stop`).
    Stopped = 0,
    /// A worker thread has been spawned and stream setup is in progress.
    Starting = 1,
    /// The FSEventStream was created and started; callbacks are being delivered.
    Active = 2,
    /// The last `start` attempt failed during setup; no watcher is running.
    Failed = 3,
}

impl WatcherStatus {
    /// C-compatible integer value for FFI export.
    pub fn as_c_int(self) -> i32 {
        self as i32
    }
}

/// Current lifecycle status of the watcher. Updated by `start`/`stop` at
/// every transition; read by `status()` (and the `ff_fsevents_status` FFI).
static WATCHER_STATUS: Mutex<WatcherStatus> = Mutex::new(WatcherStatus::Stopped);

/// Test-only hook: when set, the next `start` call fails synchronously with
/// a deterministic setup failure (no worker thread is spawned). Lets FFI
/// integration tests prove that `ff_fsevents_start` reports failure instead
/// of a false success without depending on platform CF behavior.
#[cfg(test)]
pub(crate) static FORCE_SETUP_FAILURE: AtomicBool = AtomicBool::new(false);

/// Callback type for FSEvents notifications.
/// Arguments: (path, user_data)
pub type FSEventCallback = extern "C" fn(path: *const c_char, user_data: *mut c_void);

/// Raw-pointer wrapper that makes `CFRunLoopRef` shareable across threads.
///
/// The run-loop pointer is only ever dereferenced inside `macos` FFI calls
/// after being retrieved from the shared slot (which is only written by the
/// worker before entering the run loop and only read by `stop_internal`),
/// so marking it `Send` is safe.
#[cfg(target_os = "macos")]
#[derive(Clone, Copy)]
struct SendPtr(*mut c_void);

#[cfg(target_os = "macos")]
unsafe impl Send for SendPtr {}

// ── macOS: real FSEventStream implementation ────────────────────────

#[cfg(target_os = "macos")]
mod macos {
    use super::*;
    use std::ffi::CStr;

    // ── CoreFoundation / FSEvents opaque types ──────────────────────
    pub type CFTypeRef = *const c_void;
    pub type CFAllocatorRef = *const c_void;
    pub type CFArrayRef = *const c_void;
    pub type CFStringRef = *const c_void;
    pub type CFRunLoopRef = *mut c_void;
    pub type CFIndex = isize;
    pub type CFTimeInterval = f64;
    pub type CFStringEncoding = u32;
    pub type Boolean = u8;
    pub type FSEventStreamRef = *const c_void;
    pub type ConstFSEventStreamRef = *const c_void;
    pub type FSEventStreamEventId = u64;
    pub type FSEventStreamEventFlags = u32;
    pub type FSEventStreamCreateFlags = u32;

    pub const kCFStringEncodingUTF8: CFStringEncoding = 0x0800_0100;
    /// Watch from "now" — do not replay the past.
    pub const kFSEventStreamEventIdSinceNow: FSEventStreamEventId = 0xFFFF_FFFF_FFFF_FFFF;
    /// Deliver file-level events (paths for individual file changes).
    pub const kFSEventStreamCreateFlagFileEvents: FSEventStreamCreateFlags = 0x0000_0010;

    /// FSEvents callback signature.
    ///
    /// With `kFSEventStreamCreateFlagUseCFTypes` *not* set, `event_paths` is
    /// a C array of `const char *` of length `num_events` (no CF plumbing
    /// needed on the callback hot path).
    pub type FSEventStreamCallback = extern "C" fn(
        stream_ref: ConstFSEventStreamRef,
        client_call_back_info: *mut c_void,
        num_events: usize,
        event_paths: *mut c_void,
        event_flags: *const FSEventStreamEventFlags,
        event_ids: *const FSEventStreamEventId,
    );

    /// Context handed to `FSEventStreamCreate` (mirrors `FSEventStreamContext`).
    #[repr(C)]
    pub struct FSEventStreamContext {
        version: CFIndex,
        info: *mut c_void,
        retain: Option<unsafe extern "C" fn(*const c_void) -> *const c_void>,
        release: Option<unsafe extern "C" fn(*const c_void)>,
        copy_description: Option<unsafe extern "C" fn(*const c_void) -> CFStringRef>,
    }

    /// Callbacks passed to `CFArrayCreate` (mirrors `CFArrayCallBacks`).
    #[repr(C)]
    pub struct CFArrayCallBacks {
        version: CFIndex,
        retain: Option<unsafe extern "C" fn(*const c_void) -> *const c_void>,
        release: Option<unsafe extern "C" fn(*const c_void)>,
        copy_description: Option<unsafe extern "C" fn(*const c_void) -> CFStringRef>,
        equal: Option<unsafe extern "C" fn(*const c_void, *const c_void) -> Boolean>,
    }

    // FSEvents symbols live in the CoreServices framework.
    #[link(name = "CoreServices", kind = "framework")]
    extern "C" {
        // ── FSEvents ──
        pub fn FSEventStreamCreate(
            allocator: CFAllocatorRef,
            callback: FSEventStreamCallback,
            context: *mut FSEventStreamContext,
            paths_to_watch: CFArrayRef,
            since_when: FSEventStreamEventId,
            latency: CFTimeInterval,
            flags: FSEventStreamCreateFlags,
        ) -> FSEventStreamRef;
        pub fn FSEventStreamScheduleWithRunLoop(
            stream_ref: FSEventStreamRef,
            run_loop: CFRunLoopRef,
            run_loop_mode: CFStringRef,
        );
        pub fn FSEventStreamStart(stream_ref: FSEventStreamRef) -> Boolean;
        pub fn FSEventStreamStop(stream_ref: FSEventStreamRef);
        pub fn FSEventStreamInvalidate(stream_ref: FSEventStreamRef);
        pub fn FSEventStreamRelease(stream_ref: FSEventStreamRef);

        // ── CoreFoundation ──
        pub fn CFArrayCreate(
            allocator: CFAllocatorRef,
            values: *const CFTypeRef,
            num_values: CFIndex,
            call_backs: *const CFArrayCallBacks,
        ) -> CFArrayRef;
        pub fn CFStringCreateWithCString(
            allocator: CFAllocatorRef,
            c_str: *const c_char,
            encoding: CFStringEncoding,
        ) -> CFStringRef;
        pub fn CFRelease(cf: CFTypeRef);
        pub fn CFRunLoopGetCurrent() -> CFRunLoopRef;
        pub fn CFRunLoopRun();
        pub fn CFRunLoopStop(run_loop: CFRunLoopRef);

        pub static kCFAllocatorDefault: CFAllocatorRef;
        pub static kCFRunLoopDefaultMode: CFStringRef;
        pub static kCFTypeArrayCallBacks: CFArrayCallBacks;
    }

    /// Payload passed to the FSEventStream via `context.info`. Owns the
    /// external callback, the user-data pointer, and a reference to the
    /// stop flag so the callback can also tear the run loop down.
    struct CallbackInfo {
        callback: FSEventCallback,
        user_data: *mut c_void,
        stop_flag: Arc<AtomicBool>,
    }

    /// Latency (seconds) passed to `FSEventStreamCreate`. This is the
    /// debounce window: events arriving within 300 ms are coalesced by
    /// FSEvents into a single callback invocation.
    const LATENCY: CFTimeInterval = 0.3;
    const FLAGS: FSEventStreamCreateFlags = kFSEventStreamCreateFlagFileEvents;

    /// FSEvents delivery callback — runs on the worker thread's run loop.
    ///
    /// `event_paths` is a `const char **` array (UseCFTypes flag is off).
    /// A 300 ms debounce is enforced by the stream's `latency`; additionally
    /// we honor the stop flag here so a late burst can unblock the run loop.
    extern "C" fn on_fsevent(
        _stream_ref: ConstFSEventStreamRef,
        info: *mut c_void,
        num_events: usize,
        event_paths: *mut c_void,
        _event_flags: *const FSEventStreamEventFlags,
        _event_ids: *const FSEventStreamEventId,
    ) {
        // Safety: `info` is the `CallbackInfo` box we created in the worker
        // and which is only freed after the run loop has exited.
        let info = unsafe { &*(info as *const CallbackInfo) };
        let callback = info.callback;
        let user_data = info.user_data;

        if info.stop_flag.load(Ordering::Acquire) {
            // Shutdown requested — wake the run loop so the worker exits.
            unsafe { CFRunLoopStop(CFRunLoopGetCurrent()) };
            return;
        }

        let paths = event_paths as *const *const c_char;
        for i in 0..num_events {
            // Safety: FSEvents guarantees `num_events` valid C-string
            // pointers starting at `event_paths`.
            let path_ptr = unsafe { *paths.add(i) };
            if path_ptr.is_null() {
                continue;
            }
            let path = unsafe { CStr::from_ptr(path_ptr) }
                .to_string_lossy()
                .into_owned();
            if let Ok(path_c) = CString::new(path) {
                callback(path_c.as_ptr(), user_data);
            }
        }
    }

    /// Start a real FSEventStream for `path` on macOS.
    ///
    /// A dedicated worker thread creates the stream on its own run loop and
    /// blocks in `CFRunLoopRun()` until `stop()` signals via `CFRunLoopStop`.
    /// The stream + run loop are published through shared slots so `stop()`
    /// (running on another thread) can wake the loop.
    ///
    /// Setup runs on the worker, so its result is reported back through a
    /// channel and `start_macos` blocks until setup has *finished*. A failed
    /// setup therefore returns `FSEVENTS_ERR` instead of a false success.
    pub fn start_macos(
        path: &str,
        callback: FSEventCallback,
        user_data: *mut c_void,
    ) -> i32 {
        let path_bytes: Vec<u8> = path.as_bytes().to_vec();
        let user_data_addr = user_data as usize;
        let stop_flag = Arc::new(AtomicBool::new(false));

        let run_loop_slot = Arc::new(Mutex::new(None::<SendPtr>));
        let ready = Arc::new(Mutex::new(false));
        let ready_cvar = Arc::new(Condvar::new());
        // Setup-result channel: the worker sends its setup outcome here so
        // `start_macos` can observe the real result synchronously.
        let (setup_tx, setup_rx) = mpsc::channel::<Result<(), ()>>();

        let w_run_loop = run_loop_slot.clone();
        let w_ready = ready.clone();
        let w_cvar = ready_cvar.clone();
        let w_stop = stop_flag.clone();

        let handle = thread::spawn(move || {
            // Setup phase. Publishes the run loop + signals `ready` exactly
            // once, whether setup succeeds (before entering the run loop) or
            // fails (before returning), then reports the outcome through the
            // setup channel so the caller can observe it synchronously.
            let setup: Result<(macos::FSEventStreamRef, *mut c_void, CFTypeRef, CFTypeRef), ()> =
                (|| {
                    let path_c = CString::new(path_bytes).map_err(|_| ())?;
                    let path_str = unsafe {
                        CFStringCreateWithCString(
                            kCFAllocatorDefault,
                            path_c.as_ptr(),
                            kCFStringEncodingUTF8,
                        )
                    };
                    if path_str.is_null() {
                        return Err(());
                    }
                    let paths_arr = [path_str as CFTypeRef; 1];
                    let paths = unsafe {
                        CFArrayCreate(
                            kCFAllocatorDefault,
                            paths_arr.as_ptr(),
                            1,
                            &kCFTypeArrayCallBacks,
                        )
                    };
                    if paths.is_null() {
                        unsafe { CFRelease(path_str) };
                        return Err(());
                    }

                    let info_box = Box::new(CallbackInfo {
                        callback,
                        user_data: user_data_addr as *mut c_void,
                        stop_flag: w_stop.clone(),
                    });
                    let info_ptr = Box::into_raw(info_box) as *mut c_void;
                    let mut context = FSEventStreamContext {
                        version: 0,
                        info: info_ptr,
                        retain: None,
                        release: None,
                        copy_description: None,
                    };

                    let stream = unsafe {
                        FSEventStreamCreate(
                            kCFAllocatorDefault,
                            on_fsevent,
                            &mut context,
                            paths,
                            kFSEventStreamEventIdSinceNow,
                            LATENCY,
                            FLAGS,
                        )
                    };
                    if stream.is_null() {
                        let _ = unsafe { Box::from_raw(info_ptr as *mut CallbackInfo) };
                        unsafe { CFRelease(paths) };
                        unsafe { CFRelease(path_str) };
                        return Err(());
                    }

                    let rl = unsafe { CFRunLoopGetCurrent() };
                    unsafe { FSEventStreamScheduleWithRunLoop(stream, rl, kCFRunLoopDefaultMode) };
                    if unsafe { FSEventStreamStart(stream) } == 0 {
                        unsafe { FSEventStreamInvalidate(stream) };
                        unsafe { FSEventStreamRelease(stream) };
                        let _ = unsafe { Box::from_raw(info_ptr as *mut CallbackInfo) };
                        unsafe { CFRelease(paths) };
                        unsafe { CFRelease(path_str) };
                        return Err(());
                    }

                    *w_run_loop.lock() = Some(SendPtr(rl));
                    Ok((stream, info_ptr, paths, path_str))
                })();

            match setup {
                Ok((stream, info_ptr, paths, path_str)) => {
                    // Signal readiness *before* blocking so `stop()` (on
                    // another thread) can call CFRunLoopStop to wake us.
                    *w_ready.lock() = true;
                    w_cvar.notify_all();
                    let _ = setup_tx.send(Ok(()));

                    // A concurrent `stop()` may have arrived while setup was
                    // running; if so, tear down immediately instead of
                    // entering the run loop (which would otherwise block).
                    if w_stop.load(Ordering::Acquire) {
                        unsafe { FSEventStreamStop(stream) };
                        unsafe { FSEventStreamInvalidate(stream) };
                        unsafe { FSEventStreamRelease(stream) };
                        let _ = unsafe { Box::from_raw(info_ptr as *mut CallbackInfo) };
                        unsafe { CFRelease(paths) };
                        unsafe { CFRelease(path_str) };
                        return;
                    }

                    // Block until CFRunLoopStop() is called from stop().
                    unsafe { CFRunLoopRun() };

                    unsafe { FSEventStreamStop(stream) };
                    unsafe { FSEventStreamInvalidate(stream) };
                    unsafe { FSEventStreamRelease(stream) };
                    // Reclaim the CallbackInfo box we leaked into context.info.
                    let _ = unsafe { Box::from_raw(info_ptr as *mut CallbackInfo) };
                    unsafe { CFRelease(paths) };
                    unsafe { CFRelease(path_str) };
                }
                Err(()) => {
                    *w_ready.lock() = true;
                    w_cvar.notify_all();
                    let _ = setup_tx.send(Err(()));
                }
            }
        });

        // Publish the state immediately so a concurrent `stop()` can find the
        // worker while setup is still in flight (it waits on `ready`).
        let mut global = FSEVENTS_STATE.lock();
        *global = Some(FSEventsState {
            stop_flag: stop_flag.clone(),
            join_handle: Some(handle),
            run_loop: run_loop_slot,
            ready: (ready, ready_cvar),
        });
        drop(global);

        // Synchronously wait for the setup outcome. No lock is held while
        // blocked, so a concurrent `stop()` can always make progress.
        match setup_rx.recv_timeout(SETUP_TIMEOUT) {
            Ok(Ok(())) => {
                if stop_flag.load(Ordering::Acquire) {
                    // A concurrent `stop()` tore this watcher down during setup.
                    stop_internal();
                    *WATCHER_STATUS.lock() = WatcherStatus::Stopped;
                    FSEVENTS_ERR
                } else {
                    *WATCHER_STATUS.lock() = WatcherStatus::Active;
                    0
                }
            }
            Ok(Err(())) => {
                // Setup failed; the worker has already signaled `ready` and
                // exited. Reclaim it through the normal stop path.
                stop_internal();
                *WATCHER_STATUS.lock() = WatcherStatus::Failed;
                FSEVENTS_ERR
            }
            Err(_) => {
                // Pathological: the worker did not report within the timeout.
                // Signal it to stop and report failure; the worker self-cleans
                // when it wakes (it checks `stop_flag` after setup).
                stop_flag.store(true, Ordering::Release);
                *WATCHER_STATUS.lock() = WatcherStatus::Failed;
                FSEVENTS_ERR
            }
        }
    }
}

// ── Internal state ───────────────────────────────────────────────────

/// Internal state for the FSEvents watcher.
///
/// Holds everything needed to (a) signal the worker thread to stop and
/// (b) `join()` the worker thread so its resources are reclaimed.
struct FSEventsState {
    stop_flag: Arc<AtomicBool>,
    join_handle: Option<JoinHandle<()>>,
    #[cfg(target_os = "macos")]
    run_loop: Arc<Mutex<Option<SendPtr>>>,
    #[cfg(target_os = "macos")]
    ready: (Arc<Mutex<bool>>, Arc<Condvar>),
}

static FSEVENTS_STATE: Mutex<Option<FSEventsState>> = Mutex::new(None);

/// Start watching a path for filesystem changes.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path string to watch.
/// - `callback` — Function called when a change is detected.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
/// - `0` on success (the watcher is `Active` and callbacks are flowing).
/// - `FSEVENTS_ERR` (`-1`) if stream setup failed before the watcher was
///   established (the status becomes `Failed` and no watcher is running).
///
/// # Safety
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - `callback` must be a valid function pointer.
pub fn start(path: &str, callback: FSEventCallback, user_data: *mut c_void) -> i32 {
    // If a previous watcher is still registered, stop it first so we
    // don't leak its thread before overwriting the global state.
    stop_internal();

    // Test-only injection: force a deterministic setup failure so FFI
    // integration tests can prove `start` reports failure synchronously.
    #[cfg(test)]
    if FORCE_SETUP_FAILURE.swap(false, Ordering::AcqRel) {
        *WATCHER_STATUS.lock() = WatcherStatus::Failed;
        return FSEVENTS_ERR;
    }

    *WATCHER_STATUS.lock() = WatcherStatus::Starting;

    #[cfg(target_os = "macos")]
    {
        macos::start_macos(path, callback, user_data)
    }
    #[cfg(not(target_os = "macos"))]
    {
        start_fallback(path, callback, user_data)
    }
}

/// Non-macOS fallback: a polling stub that keeps the module compilable on
/// Linux/CI and preserves the `start`/`stop` lifecycle. It does not deliver
/// real events (there is no FSEvents outside macOS); it simply sleeps until
/// `stop()` sets the flag and joins the thread.
#[cfg(not(target_os = "macos"))]
fn start_fallback(path: &str, callback: FSEventCallback, user_data: *mut c_void) -> i32 {
    let stop_flag = Arc::new(AtomicBool::new(false));
    let worker_flag = stop_flag.clone();

    let path_c = match CString::new(path) {
        Ok(c) => c,
        Err(_) => {
            *WATCHER_STATUS.lock() = WatcherStatus::Failed;
            return -1;
        }
    };
    let path_box = Arc::new(path_c);
    let user_data_addr = user_data as usize;
    let worker_path = path_box.clone();

    let join_handle = thread::spawn(move || {
        let _ = (callback, user_data_addr, worker_path);
        // Poll the stop flag at a 1s granularity so `stop()` can promptly
        // tear the thread down instead of spinning forever. On platforms
        // without FSEvents, real change notifications are unavailable, so
        // no events are synthesized.
        while !worker_flag.load(Ordering::Acquire) {
            thread::sleep(Duration::from_secs(1));
        }
    });

    let mut global = FSEVENTS_STATE.lock();
    *global = Some(FSEventsState {
        stop_flag,
        join_handle: Some(join_handle),
    });
    *WATCHER_STATUS.lock() = WatcherStatus::Active;
    0
}

/// Query the current watcher lifecycle status.
pub fn status() -> WatcherStatus {
    *WATCHER_STATUS.lock()
}

/// Internal helper: stop and join the current watcher (if any) without
/// touching the global lock's contents beyond replacing it with `None`.
fn stop_internal() {
    let mut global = FSEVENTS_STATE.lock();
    if let Some(mut state) = global.take() {
        // Signal the worker to exit.
        state.stop_flag.store(true, Ordering::Release);

        #[cfg(target_os = "macos")]
        {
            // Wait until the worker has published its run loop (created and
            // started the stream) so we can stop it from this thread.
            let (ready_lock, cvar) = &state.ready;
            let mut ready = ready_lock.lock();
            if !*ready {
                cvar.wait(&mut ready);
            }
            drop(ready);

            if let Some(rl) = *state.run_loop.lock() {
                unsafe { macos::CFRunLoopStop(rl.0) };
            }
        }

        // Block until the worker has actually exited, reclaiming its stack
        // and OS thread resources.
        if let Some(handle) = state.join_handle.take() {
            let _ = handle.join();
        }

        *WATCHER_STATUS.lock() = WatcherStatus::Stopped;
    }
}

/// Stop the FSEvents watcher.
///
/// # Returns
/// - `0` on success.
/// - `-1` if no watcher is running.
pub fn stop() -> i32 {
    let was_running = FSEVENTS_STATE.lock().is_some();
    stop_internal();
    if was_running {
        0
    } else {
        -1
    }
}

// ── Tests ───────────────────────────────────────────────────────────

/// `start`/`stop` operate on the single process-global `FSEVENTS_STATE`, so
/// lifecycle tests must not run concurrently — across both the core test
/// module and the FFI test module (which share this lock). Test-only
/// synchronization; production code is untouched.
#[cfg(test)]
pub(crate) static FSEVENTS_TEST_LOCK: parking_lot::Mutex<()> = parking_lot::Mutex::new(());

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    extern "C" fn test_callback(_path: *const c_char, _user_data: *mut c_void) {}

    #[test]
    fn test_fsevents_start_stop() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        let result = start("/tmp", test_callback, ptr::null_mut());
        assert_eq!(result, 0);

        let result = stop();
        assert_eq!(result, 0);
    }

    #[test]
    fn test_fsevents_stop_without_start() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        // No watcher running → stop must report -1 (and must not panic).
        stop_internal();
        assert_eq!(stop(), -1);
    }

    #[test]
    fn test_fsevents_start_success_active() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        assert_eq!(status(), WatcherStatus::Stopped);

        let result = start("/tmp", test_callback, ptr::null_mut());
        assert_eq!(result, 0);
        assert_eq!(status(), WatcherStatus::Active);

        let result = stop();
        assert_eq!(result, 0);
        assert_eq!(status(), WatcherStatus::Stopped);
    }

    #[test]
    fn test_fsevents_start_failure_failed_status() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        // NUL byte cannot become a CString → worker setup fails.
        let result = start("watch\0me", test_callback, ptr::null_mut());
        assert_ne!(result, 0);
        assert_eq!(status(), WatcherStatus::Failed);

        // No watcher is running after a failed start: stop reports -1.
        assert_eq!(stop(), -1);

        // A subsequent successful start resets the status.
        let result = start("/tmp", test_callback, ptr::null_mut());
        assert_eq!(result, 0);
        assert_eq!(status(), WatcherStatus::Active);
        assert_eq!(stop(), 0);
        assert_eq!(status(), WatcherStatus::Stopped);
    }

    #[test]
    fn test_fsevents_stop_idempotent() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        stop_internal();
        assert_eq!(stop(), -1);
        assert_eq!(stop(), -1);
        assert_eq!(status(), WatcherStatus::Stopped);
    }

    #[test]
    fn test_fsevents_start_stop_cycles() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        for _ in 0..5 {
            assert_eq!(start("/tmp", test_callback, ptr::null_mut()), 0);
            assert_eq!(status(), WatcherStatus::Active);
            assert_eq!(stop(), 0);
            assert_eq!(status(), WatcherStatus::Stopped);
        }
    }

    // ── Wave1 regression test (v0.7.5 fix plan, red before the fix) ──
    //
    // A path with an embedded NUL byte cannot become a CString, so the macOS
    // worker's stream setup fails — yet `start_macos` returns 0 anyway.

    #[test]
    fn test_fsevents_start_failure_reported() {
        let _guard = FSEVENTS_TEST_LOCK.lock();
        let result = start("watch\0me", test_callback, ptr::null_mut());
        // Clean up the (buggy) registered watcher even if the assertion
        // below panics, so later tests do not inherit a leftover state.
        let stop_result = stop();
        assert_ne!(
            result, 0,
            "start() must report failure when the FSEvents stream cannot be created \
             (returned 0; stop() -> {})",
            stop_result
        );
        // A failed start deliberately leaves the process-global watcher
        // status at `Failed`. Restore `Stopped` so order-dependent sibling
        // tests (test_fsevents_start_success_active,
        // test_fsevents_stop_idempotent) never observe leaked state.
        *WATCHER_STATUS.lock() = WatcherStatus::Stopped;
    }
}
