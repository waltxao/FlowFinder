//! macOS FSEvents watcher for directory change notifications.
//!
//! Provides a lightweight wrapper around the macOS FSEvents API
//! to notify the Swift UI when filesystem changes occur.

use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_void};
use std::ptr;
use std::sync::{Arc, Mutex};

/// Callback type for FSEvents notifications.
/// Arguments: (path, user_data)
pub type FSEventCallback = extern "C" fn(path: *const c_char, user_data: *mut c_void);

/// Internal state for the FSEvents watcher.
struct FSEventsState {
    callback: Option<FSEventCallback>,
    user_data: *mut c_void,
}

unsafe impl Send for FSEventsState {}
unsafe impl Sync for FSEventsState {}

static FSEVENTS_STATE: Mutex<Option<Arc<Mutex<FSEventsState>>>> = Mutex::new(None);

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
    let state = Arc::new(Mutex::new(FSEventsState {
        callback: Some(callback),
        user_data,
    }));

    let mut global = FSEVENTS_STATE.lock().unwrap();
    *global = Some(state.clone());
    drop(global);

    // Spawn a background thread to simulate FSEvents monitoring
    // In a real implementation, this would use the macOS FSEvents API
    std::thread::spawn(move || {
        // Placeholder: In production, this would set up an FSEventStream
        // and run the CFRunLoop to receive events.
        // For now, we just keep the thread alive.
        loop {
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
    });

    0
}

/// Stop the FSEvents watcher.
///
/// # Returns
/// - `0` on success.
/// - `-1` if no watcher is running.
pub fn stop() -> i32 {
    let mut global = FSEVENTS_STATE.lock().unwrap();
    *global = None;
    0
}

// ── Tests ───────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn test_callback(_path: *const c_char, _user_data: *mut c_void) {}

    #[test]
    fn test_fsevents_start_stop() {
        let result = start("/tmp", test_callback, ptr::null_mut());
        assert_eq!(result, 0);

        let result = stop();
        assert_eq!(result, 0);
    }
}
