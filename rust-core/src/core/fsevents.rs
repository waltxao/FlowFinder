//! macOS FSEvents watcher for directory change notifications.
//!
//! Provides a lightweight wrapper around the macOS FSEvents API
//! to notify the Swift UI when filesystem changes occur.

use std::ffi::CString;
use std::os::raw::{c_char, c_void};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Duration;

/// Callback type for FSEvents notifications.
/// Arguments: (path, user_data)
pub type FSEventCallback = extern "C" fn(path: *const c_char, user_data: *mut c_void);

/// Internal state for the FSEvents watcher.
///
/// Holds everything needed to (a) signal the worker thread to stop and
/// (b) `join()` the worker thread so its resources are reclaimed.
///
/// Previously the worker thread ran an unbounded `loop { sleep }` and the
/// `stop()` function only cleared the global `FSEVENTS_STATE` without
/// telling the thread to exit or waiting for it — every `start`/`stop`
/// pair therefore leaked a thread (and its stack) for the lifetime of the
/// process. The `stop_flag` + `join_handle` pair below fixes that.
struct FSEventsState {
    stop_flag: Arc<AtomicBool>,
    join_handle: Option<JoinHandle<()>>,
}

unsafe impl Send for FSEventsState {}
unsafe impl Sync for FSEventsState {}

static FSEVENTS_STATE: Mutex<Option<FSEventsState>> = Mutex::new(None);

/// Start watching a path for filesystem changes.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path string to watch.
/// - `callback` — Function called when a change is detected.
/// - `user_data` — Opaque pointer passed to the callback.
///
/// # Returns
/// - `0` on success.
/// - `-1` on error.
///
/// # Safety
/// - `path` must be a valid, NUL-terminated UTF-8 string.
/// - `callback` must be a valid function pointer.
pub fn start(path: &str, callback: FSEventCallback, user_data: *mut c_void) -> i32 {
    // If a previous watcher is still registered, stop it first so we
    // don't leak its thread before overwriting the global state.
    stop_internal();

    let stop_flag = Arc::new(AtomicBool::new(false));
    let worker_flag = stop_flag.clone();

    // Keep `path` and `callback`/`user_data` alive for the worker thread.
    // `path_c` is leaked into a `Box<CString>` so we can free it after the
    // thread finishes; the worker joins before `stop()` returns, so the
    // box is dropped deterministically.
    let path_c = match CString::new(path) {
        Ok(c) => c,
        Err(_) => return -1,
    };
    let path_box = Arc::new(path_c);

    // Raw pointers (`*mut c_void`) are `!Send`, so the closure below
    // would not be `Send` and `thread::spawn` would refuse it. Convert
    // the user-data pointer to a `usize` (which is `Send`) for the trip
    // across the thread boundary; a real FSEvents implementation would
    // cast it back to `*mut c_void` before invoking `callback`.
    let user_data_addr = user_data as usize;
    let worker_path = path_box.clone();
    let join_handle = thread::spawn(move || {
        // Placeholder: In production, this would set up an FSEventStream
        // and run the CFRunLoop to receive events. For now, we poll the
        // stop flag at a 1s granularity so `stop()` can promptly tear the
        // thread down instead of spinning forever.
        // `callback`, `user_data_addr`, and `worker_path` are intentionally
        // unused here — a real FSEvents implementation would invoke
        // `callback(path_ptr, user_data_addr as *mut c_void)` on each
        // event. We reference them to keep the closure's captures
        // explicit and avoid "unused variable" warnings getting promoted
        // to errors in stricter builds.
        let _ = (callback, user_data_addr, worker_path);
        while !worker_flag.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_secs(1));
        }
    });

    let mut global = FSEVENTS_STATE.lock().unwrap();
    *global = Some(FSEventsState {
        stop_flag,
        join_handle: Some(join_handle),
    });

    0
}

/// Internal helper: stop and join the current watcher (if any) without
/// touching the global lock's contents beyond replacing it with `None`.
fn stop_internal() {
    let mut global = FSEVENTS_STATE.lock().unwrap();
    if let Some(mut state) = global.take() {
        // Signal the worker to exit its polling loop.
        state.stop_flag.store(true, Ordering::Relaxed);
        // Block until the worker has actually exited, reclaiming its
        // stack and OS thread resources. A real FSEvents implementation
        // would additionally `CFRunLoopStop()` here; the placeholder
        // worker only sleeps, so `join` returns within ~1s.
        if let Some(handle) = state.join_handle.take() {
            let _ = handle.join();
        }
    }
}

/// Stop the FSEvents watcher.
///
/// # Returns
/// - `0` on success.
/// - `-1` if no watcher is running.
pub fn stop() -> i32 {
    let was_running = FSEVENTS_STATE
        .lock()
        .unwrap()
        .is_some();
    stop_internal();
    if was_running { 0 } else { -1 }
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    extern "C" fn test_callback(_path: *const c_char, _user_data: *mut c_void) {}

    #[test]
    fn test_fsevents_start_stop() {
        let result = start("/tmp", test_callback, ptr::null_mut());
        assert_eq!(result, 0);

        let result = stop();
        assert_eq!(result, 0);
    }
}
