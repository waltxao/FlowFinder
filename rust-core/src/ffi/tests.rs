//! FFI 测试模块（从 mod.rs 拆出，T14）。
//!
//! 由 `mod.rs` 的 `#[cfg(test)] mod tests;` 引入；内容与原内联测试一致。

use super::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_void;
use std::ptr;
use std::sync::{Arc, Mutex};

    use super::*;

    #[test]
    fn test_rust_string_to_c_roundtrip() {
        let original = "hello world".to_string();
        let c_ptr = rust_string_to_c(original.clone());
        assert!(!c_ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(c_ptr);
            assert_eq!(cstr.to_str().unwrap(), "hello world");
            let _ = CString::from_raw(c_ptr);
        }
    }

    #[test]
    fn test_ff_free_string_null() {
        // Should not panic.
        ff_free_string(ptr::null_mut());
    }

    #[test]
    fn test_ff_version_string() {
        let ptr = ff_version_string();
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            assert!(!cstr.to_str().unwrap().is_empty());
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_get_file_type() {
        let path = CString::new("/test/document.pdf").unwrap();
        let ptr = ff_get_file_type(path.as_ptr());
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            assert_eq!(cstr.to_str().unwrap(), "pdf");
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_get_file_type_no_extension() {
        let path = CString::new("/test/README").unwrap();
        let ptr = ff_get_file_type(path.as_ptr());
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            assert_eq!(cstr.to_str().unwrap(), "");
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_get_file_type_null() {
        let ptr = ff_get_file_type(ptr::null());
        assert!(ptr.is_null());
    }

    #[test]
    fn test_ff_cache_invalidate() {
        let path = CString::new("/tmp/test_cache").unwrap();
        let result = ff_cache_invalidate(path.as_ptr());
        assert_eq!(result, FF_OK);
    }

    #[test]
    fn test_ff_cache_invalidate_null() {
        let result = ff_cache_invalidate(ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_cache_get_miss() {
        let path = CString::new("/nonexistent/path/xyz123").unwrap();
        let result = ff_cache_get(path.as_ptr(), dummy_callback, ptr::null_mut());
        assert_eq!(result, FF_ERR_NOT_FOUND);
    }

    #[test]
    fn test_ff_dir_cache_clear() {
        let result = ff_dir_cache_clear();
        assert_eq!(result, FF_OK);
    }

    #[test]
    fn test_ff_cache_init_null() {
        let result = ff_cache_init(ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    // ── L1 + L2 two-tier cache integration ──────────────────────────
    //
    // Verifies the full FFI flow: ff_cache_init → ff_cache_put writes to
    // both L1 and L2; clearing L1 (dir_cache::clear) forces an L1 miss;
    // ff_cache_get must then recover the entries from L2 and deliver them
    // through the callback.
    //
    // The global `CACHE_DB_PATH` is a `OnceLock<String>` — once set by the
    // first `ff_cache_init` call it cannot be reset. Tests in the same
    // process therefore share whichever path was set first; this test is
    // written to be robust to that constraint (it queries a unique dir path
    // that no other test populates).

    #[test]
    fn test_ff_cache_l2_recovery_after_l1_clear() {
        use std::sync::Mutex as StdMutex;
        // A process-global lock so this test doesn't race with other tests
        // that touch the cache while we're mid-verify.
        static L2_TEST_LOCK: StdMutex<()> = StdMutex::new(());

        let _guard = L2_TEST_LOCK.lock().unwrap();

        // Use a fresh temp file for the SQLite db. If a prior test in this
        // process already called ff_cache_init, the OnceLock will retain the
        // old path — that's fine: init_cache is idempotent (CREATE TABLE IF
        // NOT EXISTS) and we still verify the L2 round-trip below.
        let tmp = tempfile::NamedTempFile::new().expect("create temp file");
        let db_path = tmp.path().to_str().expect("utf-8 path").to_string();
        let db_path_c = CString::new(db_path.clone()).unwrap();
        let init_result = ff_cache_init(db_path_c.as_ptr());
        assert_eq!(init_result, FF_OK, "ff_cache_init should succeed");

        // Currently-active global db path (may differ from `db_path` if a
        // prior test in this process already initialized the OnceLock).
        let active_db = CACHE_DB_PATH.get().map(|s| s.as_str()).unwrap_or(&db_path);

        // Unique dir path to avoid collisions with other tests.
        let dir_path_str =
            "/tmp/flowfinder_test_l2_recovery_unique_8f3a2c";
        let dir_path = CString::new(dir_path_str).unwrap();

        // Build Rust-owned skeletons first — used both for seeding L2
        // directly (if needed) and as the source of truth for the entries.
        let skeletons: Vec<crate::core::scanner::FileEntrySkeleton> = vec![
            crate::core::scanner::FileEntrySkeleton {
                id: "/tmp/flowfinder_test_l2_recovery_unique_8f3a2c/alpha.txt".to_string(),
                name: "alpha.txt".to_string(),
                path: "/tmp/flowfinder_test_l2_recovery_unique_8f3a2c/alpha.txt".to_string(),
                is_dir: false,
                is_file: true,
                is_symlink: false,
                is_hidden: false,
                extension: "txt".to_string(),
                size: 100,
                modified: 1_000,
                created: 900,
                is_system_protected: false,
                metadata_loaded: true,
            },
            crate::core::scanner::FileEntrySkeleton {
                id: "/tmp/flowfinder_test_l2_recovery_unique_8f3a2c/beta_dir".to_string(),
                name: "beta_dir".to_string(),
                path: "/tmp/flowfinder_test_l2_recovery_unique_8f3a2c/beta_dir".to_string(),
                is_dir: true,
                is_file: false,
                is_symlink: false,
                is_hidden: false,
                extension: String::new(),
                size: 0,
                modified: 2_000,
                created: 1_900,
                is_system_protected: false,
                metadata_loaded: true,
            },
        ];

        // Build matching FFEntryRef array with heap-allocated C strings.
        let name1 = CString::new("alpha.txt").unwrap().into_raw();
        let path1 = CString::new("/tmp/flowfinder_test_l2_recovery_unique_8f3a2c/alpha.txt")
            .unwrap()
            .into_raw();
        let ext1 = CString::new("txt").unwrap().into_raw();
        let name2 = CString::new("beta_dir").unwrap().into_raw();
        let path2 = CString::new("/tmp/flowfinder_test_l2_recovery_unique_8f3a2c/beta_dir")
            .unwrap()
            .into_raw();
        let ext2 = CString::new("").unwrap().into_raw();

        let entries: [FFEntryRef; 2] = [
            FFEntryRef {
                name: name1,
                path: path1,
                extension: ext1,
                is_dir: false,
                is_file: true,
                is_symlink: false,
                is_hidden: false,
                is_system_protected: false,
                size: 100,
                modified: 1_000,
                created: 900,
            },
            FFEntryRef {
                name: name2,
                path: path2,
                extension: ext2,
                is_dir: true,
                is_file: false,
                is_symlink: false,
                is_hidden: false,
                is_system_protected: false,
                size: 0,
                modified: 2_000,
                created: 1_900,
            },
        ];

        // ff_cache_put → writes L1 (and L2 if the global path is set).
        let put_result = ff_cache_put(dir_path.as_ptr(), entries.as_ptr(), entries.len());
        assert_eq!(put_result, FF_OK, "ff_cache_put should succeed");

        // Reclaim the C strings we handed to ff_cache_put (the FFI copies
        // them into Rust-owned Strings internally — the raw pointers are
        // no longer needed after ff_cache_put returns).
        for raw in [name1, path1, ext1, name2, path2, ext2] {
            unsafe { let _ = CString::from_raw(raw); }
        }

        // Defensive: ensure L2 actually has the rows for our dir path,
        // seeding directly via sqlite_cache::cache_put if the global
        // OnceLock pointed elsewhere (e.g. a prior test set a different
        // path). Without this, the recovery assertion below would be
        // vacuous in such a scenario.
        let seeded = matches!(
            crate::core::sqlite_cache::cache_get(active_db, dir_path_str),
            Ok(Some(v)) if !v.is_empty()
        );
        if !seeded {
            crate::core::sqlite_cache::cache_put(active_db, dir_path_str, &skeletons)
                .expect("seed L2 directly");
        }

        // Clear L1 so the next ff_cache_get MUST come from L2.
        crate::core::dir_cache::clear();

        // Collect entries delivered via the callback.
        #[derive(Default)]
        struct Collector {
            names: Vec<String>,
            is_dirs: Vec<bool>,
            sizes: Vec<u64>,
        }

        extern "C" fn collect_cb(
            entry: *const FFEntryRef,
            user_data: *mut c_void,
        ) {
            unsafe {
                let entry = &*entry;
                let collector = &mut *(user_data as *mut Collector);
                collector.names.push(
                    CStr::from_ptr(entry.name).to_string_lossy().to_string(),
                );
                collector.is_dirs.push(entry.is_dir);
                collector.sizes.push(entry.size);
            }
        }

        let mut collector = Collector::default();
        let get_result = ff_cache_get(
            dir_path.as_ptr(),
            collect_cb,
            &mut collector as *mut Collector as *mut c_void,
        );

        assert_eq!(
            get_result, FF_OK,
            "ff_cache_get must recover from L2 after L1 clear"
        );
        assert_eq!(
            collector.names.len(),
            2,
            "callback should receive both entries"
        );
        assert!(collector.names.contains(&"alpha.txt".to_string()));
        assert!(collector.names.contains(&"beta_dir".to_string()));
        assert!(collector.is_dirs.contains(&true));
        assert!(collector.is_dirs.contains(&false));
        assert!(collector.sizes.contains(&100));

        // Cleanup: invalidate the L2 row for our dir path so re-runs stay clean.
        let _ = crate::core::sqlite_cache::cache_invalidate(active_db, dir_path_str);
        crate::core::dir_cache::clear();
    }

    #[test]
    fn test_ff_cache_get_empty_dir_l2_hit() {
        use std::sync::Mutex as StdMutex;
        static L2_TEST_LOCK: StdMutex<()> = StdMutex::new(());

        let _guard = L2_TEST_LOCK.lock().unwrap();

        // Fresh temp db; if a prior test already set the OnceLock the schema
        // is re-asserted idempotently and the active path is used below.
        let tmp = tempfile::NamedTempFile::new().expect("create temp file");
        let db_path = tmp.path().to_str().expect("utf-8 path").to_string();
        let db_path_c = CString::new(db_path.clone()).unwrap();
        let init_result = ff_cache_init(db_path_c.as_ptr());
        assert_eq!(init_result, FF_OK, "ff_cache_init should succeed");

        let active_db = CACHE_DB_PATH.get().map(|s| s.as_str()).unwrap_or(&db_path);

        // Unique dir path to avoid collisions with other tests.
        let dir_path_str = "/tmp/flowfinder_test_empty_l2_unique_9c41d7";
        let dir_path = CString::new(dir_path_str).unwrap();

        // Seed L2 with an EMPTY cache for our dir path (marker row only),
        // bypassing the FFI so L1 is not populated.
        let seeded = matches!(
            crate::core::sqlite_cache::cache_get(active_db, dir_path_str),
            Ok(Some(v)) if v.is_empty()
        );
        if !seeded {
            crate::core::sqlite_cache::cache_put(active_db, dir_path_str, &[])
                .expect("seed L2 with empty directory");
        }

        // Clear L1 so the next ff_cache_get MUST come from L2.
        crate::core::dir_cache::clear();

        extern "C" fn count_cb(_entry: *const FFEntryRef, count: *mut c_void) {
            unsafe {
                let count = &mut *(count as *mut usize);
                *count += 1;
            }
        }

        let mut callbacks = 0usize;
        let get_result = ff_cache_get(
            dir_path.as_ptr(),
            count_cb,
            &mut callbacks as *mut usize as *mut c_void,
        );

        assert_eq!(
            get_result, FF_OK,
            "a cached empty directory must be an L2 hit, not FF_ERR_NOT_FOUND"
        );
        assert_eq!(callbacks, 0, "empty directory must deliver zero entries");

        // Cleanup: invalidate the L2 marker row so re-runs stay clean.
        let _ = crate::core::sqlite_cache::cache_invalidate(active_db, dir_path_str);
        crate::core::dir_cache::clear();
    }

    #[test]
    fn test_ff_fsevents_start_stop() {
        let _guard = crate::core::fsevents::FSEVENTS_TEST_LOCK.lock();
        extern "C" fn test_callback(_path: *const c_char, _user_data: *mut c_void) {}

        let path = CString::new("/tmp").unwrap();
        let result = ff_fsevents_start(path.as_ptr(), test_callback, ptr::null_mut());
        assert_eq!(result, FF_OK);

        let result = ff_fsevents_stop(0);
        assert_eq!(result, FF_OK);
    }

    #[test]
    fn test_ff_fsevents_status_transitions() {
        let _guard = crate::core::fsevents::FSEVENTS_TEST_LOCK.lock();
        extern "C" fn test_callback(_path: *const c_char, _user_data: *mut c_void) {}

        let path = CString::new("/tmp").unwrap();
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_STOPPED);

        let result = ff_fsevents_start(path.as_ptr(), test_callback, ptr::null_mut());
        assert_eq!(result, FF_OK);
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_ACTIVE);

        let result = ff_fsevents_stop(0);
        assert_eq!(result, FF_OK);
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_STOPPED);
    }

    #[test]
    fn test_ff_fsevents_start_failure_reported() {
        let _guard = crate::core::fsevents::FSEVENTS_TEST_LOCK.lock();
        extern "C" fn test_callback(_path: *const c_char, _user_data: *mut c_void) {}

        // Inject a deterministic setup failure (test-only hook in core).
        crate::core::fsevents::FORCE_SETUP_FAILURE.store(true, std::sync::atomic::Ordering::Release);

        let path = CString::new("/tmp").unwrap();
        let result = ff_fsevents_start(path.as_ptr(), test_callback, ptr::null_mut());
        assert_eq!(result, FF_ERR_IO);
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_FAILED);

        // No watcher is running after a failed start; stop stays idempotent.
        let result = ff_fsevents_stop(0);
        assert_eq!(result, FF_OK);
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_FAILED);

        // Restore a stopped watcher so sibling tests in this module observe
        // the same initial status regardless of parallel execution order.
        let _ = ff_fsevents_start(path.as_ptr(), test_callback, ptr::null_mut());
        let _ = ff_fsevents_stop(0);
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn test_ff_fsevents_callback_receives_path() {
        let _guard = crate::core::fsevents::FSEVENTS_TEST_LOCK.lock();
        use std::time::{Duration, Instant};

        static CALLBACK_PATHS: parking_lot::Mutex<Vec<String>> = parking_lot::Mutex::new(Vec::new());

        extern "C" fn record_callback(path: *const c_char, _user_data: *mut c_void) {
            if path.is_null() {
                return;
            }
            let p = unsafe { CStr::from_ptr(path) }.to_string_lossy().into_owned();
            CALLBACK_PATHS.lock().push(p);
        }

        let marker = format!(
            "/tmp/ff_fsevents_cb_{}_{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let path = CString::new("/tmp").unwrap();
        let result = ff_fsevents_start(path.as_ptr(), record_callback, ptr::null_mut());
        assert_eq!(result, FF_OK);
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_ACTIVE);

        // Create a file under /tmp to trigger an FSEvents callback.
        std::fs::write(&marker, b"x").unwrap();

        let deadline = Instant::now() + Duration::from_secs(5);
        let mut hit = false;
        while Instant::now() < deadline {
            if CALLBACK_PATHS.lock().iter().any(|p| p.contains("ff_fsevents_cb_")) {
                hit = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(50));
        }

        let _ = std::fs::remove_file(&marker);
        let stop_result = ff_fsevents_stop(0);
        assert_eq!(stop_result, FF_OK);
        assert_eq!(ff_fsevents_status(), FF_FSEVENTS_STATUS_STOPPED);
        assert!(hit, "FSEvents callback did not deliver the created path within 5s");
    }

    extern "C" fn dummy_callback(_entry: *const FFEntryRef, _user_data: *mut c_void) {}

    // ── Settings Tests ────────────────────────────────────────────────

    #[test]
    fn test_ff_settings_load() {
        let ptr = ff_settings_load();
        assert!(!ptr.is_null());
        unsafe {
            let cstr = CStr::from_ptr(ptr);
            let json = cstr.to_str().unwrap();
            assert!(json.contains("general"));
            assert!(json.contains("appearance"));
            assert!(json.contains("shortcuts"));
            assert!(json.contains("advanced"));
            let _ = CString::from_raw(ptr);
        }
    }

    #[test]
    fn test_ff_settings_get_set() {
        // Set a value
        let key = CString::new("appearance.theme").unwrap();
        let value = CString::new("dark").unwrap();
        let result = ff_settings_set(key.as_ptr(), value.as_ptr());
        assert_eq!(result, FF_OK);

        // Get the value back
        let result = ff_settings_get(key.as_ptr());
        assert!(!result.is_null());
        unsafe {
            let cstr = CStr::from_ptr(result);
            assert_eq!(cstr.to_str().unwrap(), "dark");
            let _ = CString::from_raw(result);
        }
    }

    #[test]
    fn test_ff_settings_get_invalid_key() {
        let key = CString::new("invalid.key").unwrap();
        let result = ff_settings_get(key.as_ptr());
        assert!(result.is_null());
    }

    #[test]
    fn test_ff_settings_set_null() {
        let result = ff_settings_set(std::ptr::null(), std::ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_settings_save() {
        let json = r#"{"general":{"default_directory":"/test","show_hidden_files":true,"confirm_delete":false},"appearance":{"theme":"light","icon_size":48,"font_size":14},"shortcuts":{"new_window":"Cmd+N","close_window":"Cmd+W","search":"Cmd+F","refresh":"Cmd+R","delete":"Cmd+Backspace","copy":"Cmd+C","paste":"Cmd+V","select_all":"Cmd+A"},"advanced":{"cache_size_mb":200,"thumbnail_quality":90,"fsevents_enabled":false}}"#;
        let c_json = CString::new(json).unwrap();
        let result = ff_settings_save(c_json.as_ptr());
        assert_eq!(result, FF_OK);

        // Verify the saved value
        let key = CString::new("appearance.theme").unwrap();
        let result = ff_settings_get(key.as_ptr());
        assert!(!result.is_null());
        unsafe {
            let cstr = CStr::from_ptr(result);
            assert_eq!(cstr.to_str().unwrap(), "light");
            let _ = CString::from_raw(result);
        }
    }

    // ── Task Scheduler Tests ──────────────────────────────────────────

    #[test]
    fn test_ff_task_submit() {
        let name = CString::new("copy").unwrap();
        let description = CString::new("test description").unwrap();
        let mut out_task_id: *mut c_char = std::ptr::null_mut();

        let result = crate::core::task_scheduler::ff_task_submit(
            name.as_ptr(),
            description.as_ptr(),
            1,
            &mut out_task_id,
        );
        assert_eq!(result, FF_OK);
        assert!(!out_task_id.is_null());
        unsafe {
            let _ = CString::from_raw(out_task_id);
        }
    }

    #[test]
    fn test_ff_task_submit_invalid_type() {
        let name = CString::new("invalid").unwrap();
        let mut out_task_id: *mut c_char = std::ptr::null_mut();
        let result = crate::core::task_scheduler::ff_task_submit(
            name.as_ptr(),
            std::ptr::null(),
            1,
            &mut out_task_id,
        );
        assert_eq!(result, FF_ERR_GENERIC);
    }

    #[test]
    fn test_ff_task_cancel_not_found() {
        let task_id = CString::new("99999").unwrap();
        let result = crate::core::task_scheduler::ff_task_cancel(task_id.as_ptr());
        assert_eq!(result, FF_ERR_NOT_FOUND);
    }

    // ── Wave3 T9: task lifecycle + failure paths ──────────────────────

    /// Collects `FFTaskInfo` ids/statuses into the `Vec<(String, i32)>`
    /// passed as `user_data`, so parallel tests never share state.
    extern "C" fn collect_task_info(task: *const FFTaskInfo, user_data: *mut c_void) {
        if task.is_null() || user_data.is_null() {
            return;
        }
        let hits = unsafe { &mut *(user_data as *mut Vec<(String, i32)>) };
        let t = unsafe { &*task };
        let id = if t.id.is_null() {
            String::new()
        } else {
            unsafe { CStr::from_ptr(t.id) }.to_string_lossy().into_owned()
        };
        hits.push((id, t.status));
    }

    fn submit_task(name: &str) -> String {
        let name_c = CString::new(name).unwrap();
        let mut out_task_id: *mut c_char = std::ptr::null_mut();
        let result = crate::core::task_scheduler::ff_task_submit(
            name_c.as_ptr(),
            std::ptr::null(),
            1,
            &mut out_task_id,
        );
        assert_eq!(result, FF_OK, "submit({name}) must succeed");
        let id = unsafe { CStr::from_ptr(out_task_id) }.to_string_lossy().into_owned();
        unsafe { let _ = CString::from_raw(out_task_id); }
        id
    }

    /// Polls `ff_task_history` until a task with `id` appears (or deadline).
    fn wait_for_history_task(id: &str, timeout: Duration) -> Vec<(String, i32)> {
        let deadline = Instant::now() + timeout;
        let mut hits: Vec<(String, i32)> = Vec::new();
        while Instant::now() < deadline {
            hits.clear();
            let result = ff_task_history(collect_task_info, &mut hits as *mut _ as *mut c_void);
            assert_eq!(result, FF_OK);
            if hits.iter().any(|(tid, _)| tid == id) {
                return hits;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        hits
    }

    #[test]
    fn test_ff_task_submit_null_name() {
        let mut out_task_id: *mut c_char = std::ptr::null_mut();
        let result = crate::core::task_scheduler::ff_task_submit(
            std::ptr::null(),
            std::ptr::null(),
            1,
            &mut out_task_id,
        );
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_submit_null_out_id() {
        let name = CString::new("copy").unwrap();
        let result = crate::core::task_scheduler::ff_task_submit(
            name.as_ptr(),
            std::ptr::null(),
            1,
            std::ptr::null_mut(),
        );
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_cancel_null() {
        let result = crate::core::task_scheduler::ff_task_cancel(std::ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_cancel_non_numeric_id() {
        let task_id = CString::new("not-a-number").unwrap();
        let result = crate::core::task_scheduler::ff_task_cancel(task_id.as_ptr());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_progress_null_args() {
        let task_id = CString::new("1").unwrap();
        assert_eq!(ff_task_progress(std::ptr::null(), std::ptr::null_mut()), FF_ERR_INVALID_PATH);
        assert_eq!(ff_task_progress(task_id.as_ptr(), std::ptr::null_mut()), FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_progress_not_found() {
        let task_id = CString::new("99999").unwrap();
        let mut progress: f64 = -1.0;
        let result = ff_task_progress(task_id.as_ptr(), &mut progress);
        assert_eq!(result, FF_ERR_NOT_FOUND);
    }

    /// A null function pointer, used to exercise the null-callback guards.
    /// `invalid_value` is allowed because producing a null fn pointer is the
    /// entire point of the helper; it is never called.
    #[allow(invalid_value)]
    fn null_task_callback() -> extern "C" fn(*const FFTaskInfo, *mut c_void) {
        unsafe { std::mem::transmute(0usize) }
    }

    #[test]
    fn test_ff_task_list_null_callback() {
        let result = ff_task_list(null_task_callback(), std::ptr::null_mut());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_history_null_callback() {
        let result = ff_task_history(null_task_callback(), std::ptr::null_mut());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_task_lifecycle_submit_progress_cancel_history_clear() {
        let _guard = crate::core::task_scheduler::TASK_TEST_LOCK.lock();
        let id = submit_task("copy");

        // Progress is queryable while the task is active.
        let id_c = CString::new(id.clone()).unwrap();
        let mut progress: f64 = -1.0;
        let result = ff_task_progress(id_c.as_ptr(), &mut progress);
        assert_eq!(result, FF_OK, "active task must report progress");
        assert!((0.0..=1.0).contains(&progress));

        // Cancel the running task.
        let result = crate::core::task_scheduler::ff_task_cancel(id_c.as_ptr());
        assert_eq!(result, FF_OK, "cancel of a live task must succeed");

        // The worker moves the cancelled task into history.
        let hits = wait_for_history_task(&id, Duration::from_secs(5));
        assert!(
            hits.iter().any(|(tid, _)| tid == &id),
            "cancelled task {id} must appear in history"
        );

        // History callback delivered the cancelled status (4).
        let (_, status) = hits.iter().find(|(tid, _)| tid == &id).unwrap();
        assert_eq!(*status, 4, "cancelled task must report status 4 (Cancelled)");

        // clear_history keeps Cancelled tasks (documented behaviour), so the
        // task must still be listed afterwards.
        assert_eq!(crate::core::task_scheduler::ff_task_clear_history(), FF_OK);
        let mut hits: Vec<(String, i32)> = Vec::new();
        assert_eq!(ff_task_history(collect_task_info, &mut hits as *mut _ as *mut c_void), FF_OK);
        assert!(
            hits.iter().any(|(tid, _)| tid == &id),
            "Cancelled task must survive clear_history"
        );
    }

    #[test]
    fn test_ff_task_history_completed_then_cleared() {
        let _guard = crate::core::task_scheduler::TASK_TEST_LOCK.lock();
        let id = submit_task("index");

        // Wait for the simulated worker to finish (10 × 100ms) and move the
        // task into history as Completed.
        let hits = wait_for_history_task(&id, Duration::from_secs(5));
        assert!(
            hits.iter().any(|(tid, _)| tid == &id),
            "completed task {id} must appear in history"
        );

        let (_, status) = hits.iter().find(|(tid, _)| tid == &id).unwrap();
        assert_eq!(*status, 2, "completed task must report status 2 (Completed)");

        // clear_history removes Completed tasks.
        assert_eq!(crate::core::task_scheduler::ff_task_clear_history(), FF_OK);
        let mut hits: Vec<(String, i32)> = Vec::new();
        assert_eq!(ff_task_history(collect_task_info, &mut hits as *mut _ as *mut c_void), FF_OK);
        assert!(
            !hits.iter().any(|(tid, _)| tid == &id),
            "Completed task must be removed by clear_history"
        );
    }

    // ── Volume Management Tests ─────────────────────────────────────

    #[test]
    fn test_ff_volume_list() {
        extern "C" fn volume_callback(
            _volume: *const FFVolumeInfo,
            _user_data: *mut c_void,
        ) {}

        let result = crate::core::volumes::ff_volume_list(volume_callback, std::ptr::null_mut());
        assert_eq!(result, FF_OK);
    }

    #[test]
    fn test_ff_volume_info_null() {
        let result = crate::core::volumes::ff_volume_info(std::ptr::null(), std::ptr::null_mut());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_volume_health_check_null() {
        // ff_volume_health_check 签名为 (path, out_result)，测试 null 路径
        let result = crate::core::volumes::ff_volume_health_check(std::ptr::null(), std::ptr::null_mut());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_volume_eject_null() {
        let result = crate::core::volumes::ff_volume_eject(std::ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    #[test]
    fn test_ff_volume_mount_null() {
        let result = crate::core::volumes::ff_volume_mount(std::ptr::null(), std::ptr::null());
        assert_eq!(result, FF_ERR_INVALID_PATH);
    }

    // ── Parallel Batch Operations Tests ─────────────────────────────

    extern "C" fn noop_batch_progress(
        _completed: usize,
        _total: usize,
        _current_file: *const c_char,
        _user_data: *mut c_void,
    ) {
    }

    /// Helper: build a `Vec<CString>` plus a `Vec<*const c_char>` view into it
    /// suitable for passing to the parallel FFI functions.
    fn build_c_string_array(paths: &[String]) -> (Vec<CString>, Vec<*const c_char>) {
        let cstrings: Vec<CString> = paths
            .iter()
            .map(|s| CString::new(s.as_str()).unwrap())
            .collect();
        let ptrs: Vec<*const c_char> = cstrings.iter().map(|cs| cs.as_ptr()).collect();
        (cstrings, ptrs)
    }

    #[test]
    fn test_ff_parallel_copy() {
        use std::fs;
        use tempfile::tempdir;

        let src_dir = tempdir().unwrap();
        let dst_dir = tempdir().unwrap();
        let n: usize = 5;

        let srcs: Vec<String> = (0..n)
            .map(|i| {
                let path = src_dir.path().join(format!("parallel_copy_{}.txt", i));
                fs::write(&path, format!("content-{}", i)).unwrap();
                path.to_str().unwrap().to_string()
            })
            .collect();

        let dst_dir_c = CString::new(dst_dir.path().to_str().unwrap()).unwrap();
        let (_cstrings, ptrs) = build_c_string_array(&srcs);

        let result = ff_parallel_copy(
            ptrs.as_ptr(),
            ptrs.len(),
            dst_dir_c.as_ptr(),
            noop_batch_progress,
            ptr::null_mut(),
        );

        assert_eq!(result as usize, n, "all {} files should copy successfully", n);

        // Verify destination files exist with correct contents.
        for i in 0..n {
            let dst = dst_dir.path().join(format!("parallel_copy_{}.txt", i));
            assert!(dst.exists(), "destination file {} should exist", i);
            assert_eq!(
                fs::read_to_string(&dst).unwrap(),
                format!("content-{}", i),
                "destination content must match source"
            );
        }
    }

    #[test]
    fn test_ff_parallel_move() {
        use std::fs;
        use tempfile::tempdir;

        let src_dir = tempdir().unwrap();
        let dst_dir = tempdir().unwrap();
        let n: usize = 3;

        let srcs: Vec<String> = (0..n)
            .map(|i| {
                let path = src_dir.path().join(format!("parallel_move_{}.txt", i));
                fs::write(&path, format!("content-{}", i)).unwrap();
                path.to_str().unwrap().to_string()
            })
            .collect();

        let dst_dir_c = CString::new(dst_dir.path().to_str().unwrap()).unwrap();
        let (_cstrings, ptrs) = build_c_string_array(&srcs);

        let result = ff_parallel_move(
            ptrs.as_ptr(),
            ptrs.len(),
            dst_dir_c.as_ptr(),
            noop_batch_progress,
            ptr::null_mut(),
        );

        assert_eq!(result as usize, n, "all {} files should move successfully", n);

        // Files must exist in destination with correct content …
        for i in 0..n {
            let dst = dst_dir.path().join(format!("parallel_move_{}.txt", i));
            assert!(dst.exists(), "destination file {} should exist", i);
            assert_eq!(
                fs::read_to_string(&dst).unwrap(),
                format!("content-{}", i),
                "destination content must match source"
            );
        }
        // … and be gone from the source.
        for src in &srcs {
            assert!(
                !std::path::Path::new(src).exists(),
                "source should be gone after move: {}",
                src
            );
        }
    }

    #[test]
    fn test_ff_parallel_copy_null_inputs() {
        let dst_dir_c = CString::new("/tmp").unwrap();
        // Non-zero count with null srcs array → FF_ERR_INVALID_PATH.
        assert_eq!(
            ff_parallel_copy(
                ptr::null(),
                3,
                dst_dir_c.as_ptr(),
                noop_batch_progress,
                ptr::null_mut(),
            ),
            FF_ERR_INVALID_PATH
        );
        // Null dst_dir → FF_ERR_INVALID_PATH.
        assert_eq!(
            ff_parallel_copy(
                ptr::null(),
                0,
                ptr::null(),
                noop_batch_progress,
                ptr::null_mut(),
            ),
            FF_ERR_INVALID_PATH
        );
    }

    #[test]
    fn test_ff_parallel_delete() {
        use std::fs;
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let n: usize = 5;

        let paths: Vec<String> = (0..n)
            .map(|i| {
                let path = dir.path().join(format!("parallel_del_{}.txt", i));
                fs::write(&path, b"to-be-deleted").unwrap();
                path.to_str().unwrap().to_string()
            })
            .collect();

        let (_cstrings, ptrs) = build_c_string_array(&paths);

        let result = ff_parallel_delete(
            ptrs.as_ptr(),
            ptrs.len(),
            noop_batch_progress,
            ptr::null_mut(),
        );

        assert_eq!(result as usize, n, "all {} files should be deleted", n);

        for p in &paths {
            assert!(!std::path::Path::new(p).exists(), "path should be gone: {}", p);
        }
    }

    #[test]
    fn test_ff_parallel_delete_null_inputs() {
        // Non-zero count with null paths array → FF_ERR_INVALID_PATH.
        assert_eq!(
            ff_parallel_delete(ptr::null(), 2, noop_batch_progress, ptr::null_mut()),
            FF_ERR_INVALID_PATH
        );
    }

    #[test]
    fn test_ff_parallel_copy_empty() {
        use tempfile::tempdir;

        let dst_dir = tempdir().unwrap();
        let dst_dir_c = CString::new(dst_dir.path().to_str().unwrap()).unwrap();
        // Empty input array (count = 0) — should succeed with 0 copies.
        let result = ff_parallel_copy(
            ptr::null(),
            0,
            dst_dir_c.as_ptr(),
            noop_batch_progress,
            ptr::null_mut(),
        );
        assert_eq!(result, 0);
    }

    /// Partial-failure path: of 5 source paths, only the first 3 exist on
    /// disk. `ff_parallel_copy` must return 3 (the success count), and
    /// `ff_last_error()` must contain the `summarize_parallel_failures`
    /// summary (`"2/5 failed: ..."`).
    #[test]
    fn test_ff_parallel_copy_partial_failure() {
        use std::fs;
        use tempfile::tempdir;

        let src_dir = tempdir().unwrap();
        let dst_dir = tempdir().unwrap();

        // Build 5 source paths but only write content to the first 3.
        // Indices 3 and 4 are never created on disk, so their copies fail.
        let srcs: Vec<String> = (0..5)
            .map(|i| {
                let path = src_dir.path().join(format!("partial_fail_{}.txt", i));
                if i < 3 {
                    fs::write(&path, format!("content-{}", i)).unwrap();
                }
                path.to_str().unwrap().to_string()
            })
            .collect();

        let dst_dir_c = CString::new(dst_dir.path().to_str().unwrap()).unwrap();
        let (_cstrings, ptrs) = build_c_string_array(&srcs);

        let result = ff_parallel_copy(
            ptrs.as_ptr(),
            ptrs.len(),
            dst_dir_c.as_ptr(),
            noop_batch_progress,
            ptr::null_mut(),
        );

        // Exactly the first 3 sources exist; the other 2 fail.
        assert_eq!(
            result, 3,
            "expected 3 of 5 copies to succeed (sources 3 and 4 do not exist)"
        );

        // `summarize_parallel_failures` must have populated `last_error`
        // with a string of the form `"2/5 failed: ..."`.
        let err_ptr = ff_last_error();
        assert!(
            !err_ptr.is_null(),
            "ff_last_error must be set on partial failure"
        );
        let err_msg = unsafe { CStr::from_ptr(err_ptr).to_string_lossy().to_string() };
        ff_free_string(err_ptr);
        assert!(
            err_msg.contains("2/5 failed"),
            "error message should contain '2/5 failed', got: {}",
            err_msg
        );

        // The 3 successful copies must land in the destination directory
        // with the correct contents.
        for i in 0..3 {
            let dst = dst_dir.path().join(format!("partial_fail_{}.txt", i));
            assert!(dst.exists(), "destination file {} should exist", i);
            assert_eq!(
                fs::read_to_string(&dst).unwrap(),
                format!("content-{}", i),
                "destination content must match source for file {}",
                i,
            );
        }
    }

    // ── ff_generate_tags tests ────────────────────────────────────

    #[test]
    fn test_ff_generate_tags_null_path() {
        let ptr = ff_generate_tags(ptr::null());
        assert!(ptr.is_null(), "null path should return null");
        let err = ff_last_error();
        assert!(!err.is_null());
        unsafe {
            let msg = CStr::from_ptr(err).to_string_lossy().to_string();
            ff_free_string(err);
            assert!(msg.contains("null"), "error should mention null, got: {}", msg);
        }
    }

    #[test]
    fn test_ff_generate_tags_nonexistent_file() {
        let path = CString::new("/nonexistent/path/file.jpg").unwrap();
        let ptr = ff_generate_tags(path.as_ptr());
        assert!(ptr.is_null(), "nonexistent file should return null");
        let err = ff_last_error();
        assert!(!err.is_null());
        unsafe {
            ff_free_string(err);
        }
    }

    #[test]
    fn test_ff_generate_tags_image_file() {
        let dir = std::env::temp_dir();
        let path = dir.join("ff_test_ffi_tags_photo.jpg");
        std::fs::write(&path, b"fake image").unwrap();

        let c_path = CString::new(path.to_str().unwrap()).unwrap();
        let ptr = ff_generate_tags(c_path.as_ptr());
        let _ = std::fs::remove_file(&path);

        assert!(!ptr.is_null(), "image file should return JSON");
        unsafe {
            let json = CStr::from_ptr(ptr).to_string_lossy().to_string();
            ff_free_string(ptr);
            assert!(json.contains("图片"), "JSON should contain 图片, got: {}", json);
            assert!(json.contains("image"), "JSON should contain image, got: {}", json);
        }
    }

    #[test]
    fn test_ff_generate_tags_unknown_type_returns_empty_array() {
        let dir = std::env::temp_dir();
        let path = dir.join("ff_test_ffi_tags_unknown.xyz123");
        std::fs::write(&path, b"data").unwrap();

        let c_path = CString::new(path.to_str().unwrap()).unwrap();
        let ptr = ff_generate_tags(c_path.as_ptr());
        let _ = std::fs::remove_file(&path);

        // 文件存在但无匹配规则 → 返回 "[]"（非 null）
        assert!(!ptr.is_null(), "existing file should return non-null even if no tags");
        unsafe {
            let json = CStr::from_ptr(ptr).to_string_lossy().to_string();
            ff_free_string(ptr);
            assert_eq!(json, "[]", "unknown type should return empty array");
        }
    }

    #[test]
    fn test_ff_generate_tags_directory() {
        let dir = std::env::temp_dir();
        let path = dir.join("ff_test_ffi_tags_dir");
        std::fs::create_dir_all(&path).unwrap();

        let c_path = CString::new(path.to_str().unwrap()).unwrap();
        let ptr = ff_generate_tags(c_path.as_ptr());
        let _ = std::fs::remove_dir_all(&path);

        assert!(!ptr.is_null());
        unsafe {
            let json = CStr::from_ptr(ptr).to_string_lossy().to_string();
            ff_free_string(ptr);
            assert!(json.contains("文件夹"), "directory should get 文件夹 tag, got: {}", json);
            assert!(json.contains("folder"), "JSON should contain folder category");
        }
    }

    // ── Wave1 regression test (v0.7.5 fix plan, red before the fix) ──
    //
    // `DEDUP_CANCEL` used to be a single process-global AtomicBool shared by
    // every scan: cancelling one scan cancelled them all, and starting a new
    // scan reset a previous scan's cancel state. Correct behaviour is per-
    // scan cancel isolation, exercised below through both the handle-based
    // API and the legacy no-handle form.

    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::time::{Duration, Instant};

    struct ScanState {
        started: AtomicBool,
        groups: AtomicUsize,
    }

    fn make_scan_state() -> *mut ScanState {
        Box::into_raw(Box::new(ScanState {
            started: AtomicBool::new(false),
            groups: AtomicUsize::new(0),
        }))
    }

    extern "C" fn dedup_progress(scanned: usize, _total: usize, user_data: *mut c_void) {
        if scanned > 0 {
            unsafe {
                (*(user_data as *mut ScanState)).started.store(true, Ordering::Relaxed);
            }
        }
    }

    extern "C" fn dedup_group(_group: *const FFDuplicateGroup, user_data: *mut c_void) {
        unsafe {
            (*(user_data as *mut ScanState)).groups.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn poll_until(what: &str, mut cond: impl FnMut() -> bool, timeout: Duration) {
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if cond() {
                return;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        panic!("timed out waiting for: {}", what);
    }

    fn make_dup_tree(root: &std::path::Path, pairs: usize) {
        for i in 0..pairs {
            let content = format!("{:06}-data-{}", i, "x".repeat(i));
            let dir = root.join(format!("pair_{:04}", i));
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("f1.bin"), &content).unwrap();
            std::fs::write(dir.join("f2.bin"), &content).unwrap();
        }
    }

    /// Allocate a heap box for the out-handle of `ff_scan_duplicates_ex`.
    /// Rust writes the handle into it *before* the scan starts; the caller
    /// reads it (volatile) from another thread to cancel the specific scan.
    fn make_handle_box() -> *mut u64 {
        Box::into_raw(Box::new(0u64))
    }

    fn read_handle_box(boxed: *mut u64) -> u64 {
        unsafe { std::ptr::read_volatile(boxed) }
    }

    #[test]
    fn test_dedup_cancel_isolated() {
        let tmp = tempfile::TempDir::new().unwrap();
        let tree_a = tmp.path().join("tree_a");
        let tree_b = tmp.path().join("tree_b");
        make_dup_tree(&tree_a, 1500); // scan A (the one being cancelled)
        make_dup_tree(&tree_b, 750); // scan B (must complete unaffected)

        let pa = CString::new(tree_a.to_string_lossy().as_bytes()).unwrap();
        let pb = CString::new(tree_b.to_string_lossy().as_bytes()).unwrap();
        let state_a = make_scan_state();
        let state_b = make_scan_state();

        // usize tokens are Send-safe; the raw pointers stay valid until the
        // handles are joined below.
        let state_a_ud = state_a as usize;
        let state_b_ud = state_b as usize;
        let handle_a = make_handle_box();
        let handle_b = make_handle_box();
        let handle_a_ud = handle_a as usize;
        let handle_b_ud = handle_b as usize;

        let thread_a = std::thread::spawn(move || {
            ff_scan_duplicates_ex(
                pa.as_ptr(),
                dedup_progress,
                dedup_group,
                state_a_ud as *mut c_void,
                handle_a_ud as *mut u64,
            )
        });
        poll_until(
            "scan A handle registered",
            || read_handle_box(handle_a) != 0,
            Duration::from_secs(60),
        );
        poll_until(
            "scan A in progress",
            || unsafe { (*(state_a as *mut ScanState)).started.load(Ordering::Relaxed) },
            Duration::from_secs(60),
        );

        let thread_b = std::thread::spawn(move || {
            ff_scan_duplicates_ex(
                pb.as_ptr(),
                dedup_progress,
                dedup_group,
                state_b_ud as *mut c_void,
                handle_b_ud as *mut u64,
            )
        });
        poll_until(
            "scan B handle registered",
            || read_handle_box(handle_b) != 0,
            Duration::from_secs(60),
        );
        poll_until(
            "scan B in progress",
            || unsafe { (*(state_b as *mut ScanState)).started.load(Ordering::Relaxed) },
            Duration::from_secs(60),
        );

        // Cancel scan A by its handle only; scan B's private flag is untouched.
        let scan_id_a = read_handle_box(handle_a);
        assert_eq!(
            ff_cancel_scan_by_id(scan_id_a),
            FF_OK,
            "cancelling a live scan must succeed"
        );

        assert_eq!(thread_a.join().unwrap(), FF_OK);
        assert_eq!(thread_b.join().unwrap(), FF_OK);

        let groups_a = unsafe { (*(state_a as *mut ScanState)).groups.load(Ordering::Relaxed) };
        let groups_b = unsafe { (*(state_b as *mut ScanState)).groups.load(Ordering::Relaxed) };
        assert!(
            groups_a < 1500,
            "cancelled scan A must stop early: got {} of 1500 groups",
            groups_a
        );
        assert_eq!(
            groups_b, 750,
            "cancelling scan A must not affect scan B: expected 750 groups, got {}",
            groups_b
        );

        // The cancelled scan has already deregistered — cancelling again is a
        // clean no-op rather than hitting a stale flag.
        assert_eq!(
            ff_cancel_scan_by_id(scan_id_a),
            FF_ERR_NOT_FOUND,
            "cancelling a finished scan must report not-found"
        );

        unsafe {
            drop(Box::from_raw(state_a));
            drop(Box::from_raw(state_b));
            drop(Box::from_raw(handle_a));
            drop(Box::from_raw(handle_b));
        }
    }

    #[test]
    fn test_dedup_cancel_noarg_isolated() {
        // Legacy no-handle `ff_cancel_scan()` targets the current scan (the
        // first-started, still-running one). Scan A is far larger than B and
        // started first, so the cancel deterministically lands on A while B
        // keeps its own fresh flag and completes with every group.
        let tmp = tempfile::TempDir::new().unwrap();
        let tree_a = tmp.path().join("tree_a");
        let tree_b = tmp.path().join("tree_b");
        make_dup_tree(&tree_a, 3000);
        make_dup_tree(&tree_b, 300);

        let pa = CString::new(tree_a.to_string_lossy().as_bytes()).unwrap();
        let pb = CString::new(tree_b.to_string_lossy().as_bytes()).unwrap();
        let state_a = make_scan_state();
        let state_b = make_scan_state();
        let state_a_ud = state_a as usize;
        let state_b_ud = state_b as usize;

        let thread_a = std::thread::spawn(move || {
            ff_scan_duplicates(pa.as_ptr(), dedup_progress, dedup_group, state_a_ud as *mut c_void)
        });
        poll_until(
            "scan A in progress",
            || unsafe { (*(state_a as *mut ScanState)).started.load(Ordering::Relaxed) },
            Duration::from_secs(60),
        );

        let thread_b = std::thread::spawn(move || {
            ff_scan_duplicates(pb.as_ptr(), dedup_progress, dedup_group, state_b_ud as *mut c_void)
        });
        poll_until(
            "scan B in progress",
            || unsafe { (*(state_b as *mut ScanState)).started.load(Ordering::Relaxed) },
            Duration::from_secs(60),
        );

        // Legacy cancel — cancels the oldest active scan (A). B is unaffected.
        ff_cancel_scan();

        assert_eq!(thread_a.join().unwrap(), FF_OK);
        assert_eq!(thread_b.join().unwrap(), FF_OK);

        let groups_b = unsafe { (*(state_b as *mut ScanState)).groups.load(Ordering::Relaxed) };
        assert_eq!(
            groups_b, 300,
            "cancelling scan A must not affect scan B: expected 300 groups, got {}",
            groups_b
        );

        unsafe {
            drop(Box::from_raw(state_a));
            drop(Box::from_raw(state_b));
        }
    }

    #[test]
    fn test_new_scan_does_not_clear_previous_cancel() {
        // A fresh scan must not reset an existing scan's cancel flag. Scan A
        // is cancelled, then scan B starts; A stays cancelled (stops early)
        // while B completes with every group on its own fresh flag.
        let tmp = tempfile::TempDir::new().unwrap();
        let tree_a = tmp.path().join("tree_a");
        let tree_b = tmp.path().join("tree_b");
        make_dup_tree(&tree_a, 2000);
        make_dup_tree(&tree_b, 200);

        let pa = CString::new(tree_a.to_string_lossy().as_bytes()).unwrap();
        let pb = CString::new(tree_b.to_string_lossy().as_bytes()).unwrap();
        let state_a = make_scan_state();
        let state_b = make_scan_state();
        let state_a_ud = state_a as usize;
        let state_b_ud = state_b as usize;
        let handle_a = make_handle_box();
        let handle_a_ud = handle_a as usize;

        let thread_a = std::thread::spawn(move || {
            ff_scan_duplicates_ex(
                pa.as_ptr(),
                dedup_progress,
                dedup_group,
                state_a_ud as *mut c_void,
                handle_a_ud as *mut u64,
            )
        });
        poll_until(
            "scan A handle registered",
            || read_handle_box(handle_a) != 0,
            Duration::from_secs(60),
        );
        poll_until(
            "scan A in progress",
            || unsafe { (*(state_a as *mut ScanState)).started.load(Ordering::Relaxed) },
            Duration::from_secs(60),
        );

        let scan_id_a = read_handle_box(handle_a);
        assert_eq!(ff_cancel_scan_by_id(scan_id_a), FF_OK);

        // Starting scan B must not clear scan A's cancelled flag.
        let thread_b = std::thread::spawn(move || {
            ff_scan_duplicates(pb.as_ptr(), dedup_progress, dedup_group, state_b_ud as *mut c_void)
        });
        poll_until(
            "scan B in progress",
            || unsafe { (*(state_b as *mut ScanState)).started.load(Ordering::Relaxed) },
            Duration::from_secs(60),
        );

        assert_eq!(thread_a.join().unwrap(), FF_OK);
        assert_eq!(thread_b.join().unwrap(), FF_OK);

        let groups_a = unsafe { (*(state_a as *mut ScanState)).groups.load(Ordering::Relaxed) };
        let groups_b = unsafe { (*(state_b as *mut ScanState)).groups.load(Ordering::Relaxed) };
        assert!(
            groups_a < 2000,
            "scan A must stay cancelled after scan B started: got {} of 2000 groups",
            groups_a
        );
        assert_eq!(
            groups_b, 200,
            "scan B must complete on its own fresh flag: expected 200 groups, got {}",
            groups_b
        );

        unsafe {
            drop(Box::from_raw(state_a));
            drop(Box::from_raw(state_b));
            drop(Box::from_raw(handle_a));
        }
    }

    // ── Wave1 T4: search cancellation and result limits (FFI level) ──

    struct SearchState {
        count: AtomicUsize,
    }

    fn make_search_state() -> *mut SearchState {
        Box::into_raw(Box::new(SearchState {
            count: AtomicUsize::new(0),
        }))
    }

    extern "C" fn search_result_count(_result: *const FFSearchResult, user_data: *mut c_void) {
        unsafe {
            (*(user_data as *mut SearchState)).count.fetch_add(1, Ordering::Relaxed);
        }
    }

    #[test]
    fn test_ff_search_ex_cancel_mid_walk() {
        let tmp = tempfile::TempDir::new().unwrap();
        // Large enough that the walk (a stat per entry) outlasts the cancel
        // request issued from the main thread right after the first result.
        let total = 15000;
        for i in 0..total {
            std::fs::write(tmp.path().join(format!("file_{:05}.txt", i)), "x").unwrap();
        }
        let root = CString::new(tmp.path().to_string_lossy().as_bytes()).unwrap();
        let query = CString::new("file").unwrap();
        let state = make_search_state();
        let state_ud = state as usize;
        let handle = make_handle_box();
        let handle_ud = handle as usize;

        let options = FFSearchOptions {
            max_results: 0,
            max_depth: 0,
        };

        let thread = std::thread::spawn(move || {
            ff_search_ex(
                root.as_ptr(),
                query.as_ptr(),
                &options,
                handle_ud as *mut u64,
                search_result_count,
                state_ud as *mut c_void,
            )
        });
        poll_until(
            "search handle registered",
            || read_handle_box(handle) != 0,
            Duration::from_secs(30),
        );
        poll_until(
            "search delivering results",
            || unsafe { (*(state as *mut SearchState)).count.load(Ordering::Relaxed) > 0 },
            Duration::from_secs(30),
        );

        let search_id = read_handle_box(handle);
        assert_eq!(
            ff_cancel_search_by_id(search_id),
            FF_OK,
            "cancelling a live search must succeed"
        );

        assert_eq!(thread.join().unwrap(), FF_OK);

        let delivered = unsafe { (*(state as *mut SearchState)).count.load(Ordering::Relaxed) };
        assert!(
            delivered < total,
            "cancelled search must stop early: delivered {} of {}",
            delivered,
            total
        );
        // Callbacks are synchronous — once the search returns, none arrive.
        assert_eq!(
            delivered,
            unsafe { (*(state as *mut SearchState)).count.load(Ordering::Relaxed) },
            "no late callbacks after search returns"
        );

        // A finished search deregisters, so cancelling again is a clean no-op.
        assert_eq!(ff_cancel_search_by_id(search_id), FF_ERR_NOT_FOUND);

        unsafe {
            drop(Box::from_raw(state));
            drop(Box::from_raw(handle));
        }
    }

    #[test]
    fn test_ff_search_ex_max_results() {
        let tmp = tempfile::TempDir::new().unwrap();
        for i in 0..10 {
            std::fs::write(tmp.path().join(format!("data_{}.txt", i)), "x").unwrap();
        }
        let root = CString::new(tmp.path().to_string_lossy().as_bytes()).unwrap();
        let query = CString::new("data").unwrap();
        let state = make_search_state();
        let state_ud = state as usize;

        let options = FFSearchOptions {
            max_results: 3,
            max_depth: 0,
        };

        let result = ff_search_ex(
            root.as_ptr(),
            query.as_ptr(),
            &options,
            ptr::null_mut(),
            search_result_count,
            state_ud as *mut c_void,
        );
        assert_eq!(result, FF_OK);

        let delivered = unsafe { (*(state as *mut SearchState)).count.load(Ordering::Relaxed) };
        assert_eq!(delivered, 3, "max_results cap must be honoured");

        unsafe {
            drop(Box::from_raw(state));
        }
    }

    // ── Wave1 T2: ff_batch_rename error mapping ──────────────────────

    /// Build a `Vec<FFRenameItem>` from `(original_path, new_name)` pairs,
    /// keeping the backing `CString`s alive for the duration of the call.
    fn build_ff_rename_items(
        items: &[(String, String)],
    ) -> (Vec<CString>, Vec<CString>, Vec<FFRenameItem>) {
        let mut originals = Vec::with_capacity(items.len());
        let mut new_names = Vec::with_capacity(items.len());
        let mut ffi_items = Vec::with_capacity(items.len());
        for (orig, new_name) in items {
            let o = CString::new(orig.as_str()).unwrap();
            let n = CString::new(new_name.as_str()).unwrap();
            ffi_items.push(FFRenameItem {
                original_path: o.as_ptr() as *mut c_char,
                new_name: n.as_ptr() as *mut c_char,
            });
            originals.push(o);
            new_names.push(n);
        }
        (originals, new_names, ffi_items)
    }

    #[test]
    fn test_ff_batch_rename_invalid_new_name_maps_to_invalid_path() {
        use std::fs;
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let src = dir.path().join("victim.txt");
        fs::write(&src, "payload").unwrap();

        for new_name in ["../escaped.txt", "/ff_abs_escape.txt", ""] {
            let (_o, _n, items) = build_ff_rename_items(&[(
                src.to_string_lossy().into_owned(),
                new_name.to_string(),
            )]);
            let result = ff_batch_rename(items.as_ptr(), items.len());
            assert_eq!(
                result,
                FF_ERR_INVALID_PATH,
                "new_name {:?} must map to FF_ERR_INVALID_PATH",
                new_name
            );
            assert!(
                src.exists(),
                "source must remain in place for new_name {:?}",
                new_name
            );
        }
    }

    #[test]
    fn test_ff_batch_rename_conflict_maps_to_io() {
        use std::fs;
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let a = dir.path().join("a.txt");
        let b = dir.path().join("b.txt");
        fs::write(&a, "alpha-payload").unwrap();
        fs::write(&b, "beta-payload").unwrap();

        let (_o, _n, items) = build_ff_rename_items(&[(
            a.to_string_lossy().into_owned(),
            "b.txt".to_string(),
        )]);
        let result = ff_batch_rename(items.as_ptr(), items.len());
        assert_eq!(result, FF_ERR_IO, "existing target must map to FF_ERR_IO");
        assert_eq!(
            fs::read_to_string(&b).unwrap(),
            "beta-payload",
            "existing target must not be overwritten"
        );
        assert!(a.exists(), "source must remain in place");
    }

    #[test]
    fn test_ff_batch_rename_valid_returns_count() {
        use std::fs;
        use tempfile::tempdir;

        let dir = tempdir().unwrap();
        let a = dir.path().join("a.txt");
        fs::write(&a, "alpha-payload").unwrap();

        let (_o, _n, items) = build_ff_rename_items(&[(
            a.to_string_lossy().into_owned(),
            "renamed.txt".to_string(),
        )]);
        let result = ff_batch_rename(items.as_ptr(), items.len());
        assert_eq!(result, 1, "legal rename must return success count");
        assert!(dir.path().join("renamed.txt").exists());
        assert!(!a.exists(), "source must be consumed by legal rename");
    }

    // ── Wave3 T9: ABI layout lock (ffi/mod.rs ↔ ff_ffi.h) ─────────────
    //
    // These tests freeze the Rust `#[repr(C)]` struct layouts against the
    // C declarations in `include/ff_ffi.h`. A silent mismatch here would
    // corrupt every struct-pointer FFI call (ff_list_dir / ff_task_list /
    // ff_volume_list / ff_search / ff_scan_duplicates / ff_batch_rename).
    //
    // Offsets below are valid on 64-bit Apple (arm64/x86_64): pointers are
    // 8 bytes/8-aligned, `bool`/`_Bool` is 1 byte/1-aligned, `u64`/`i64`
    // are 8-aligned, `i32`/enums are 4-aligned, `usize` is 8 bytes.
    // On 32-bit targets or MSVC these offsets differ; this crate only
    // targets macOS (darwin), so the assertions are unconditional.

    #[test]
    fn test_abi_ff_entry_ref_layout() {
        assert_eq!(std::mem::size_of::<FFEntryRef>(), 56);
        assert_eq!(std::mem::offset_of!(FFEntryRef, name), 0);
        assert_eq!(std::mem::offset_of!(FFEntryRef, path), 8);
        assert_eq!(std::mem::offset_of!(FFEntryRef, extension), 16);
        assert_eq!(std::mem::offset_of!(FFEntryRef, is_dir), 24);
        assert_eq!(std::mem::offset_of!(FFEntryRef, is_file), 25);
        assert_eq!(std::mem::offset_of!(FFEntryRef, is_symlink), 26);
        assert_eq!(std::mem::offset_of!(FFEntryRef, is_hidden), 27);
        assert_eq!(std::mem::offset_of!(FFEntryRef, is_system_protected), 28);
        assert_eq!(std::mem::offset_of!(FFEntryRef, size), 32);
        assert_eq!(std::mem::offset_of!(FFEntryRef, modified), 40);
        assert_eq!(std::mem::offset_of!(FFEntryRef, created), 48);
    }

    #[test]
    fn test_abi_ff_volume_info_layout() {
        assert_eq!(size_of::<FFVolumeInfo>(), 56);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, name), 0);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, path), 8);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, fs_type), 16);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, total_size), 24);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, free_size), 32);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, used_size), 40);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, is_removable), 48);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, is_ejectable), 49);
        assert_eq!(std::mem::offset_of!(FFVolumeInfo, is_writable), 50);
    }

    #[test]
    fn test_abi_ff_task_info_layout() {
        assert_eq!(size_of::<FFTaskInfo>(), 64);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, id), 0);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, name), 8);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, description), 16);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, priority), 24);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, status), 28);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, progress), 32);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, created_at), 40);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, started_at), 48);
        assert_eq!(std::mem::offset_of!(FFTaskInfo, completed_at), 56);
    }

    #[test]
    fn test_abi_ff_search_result_layout() {
        assert_eq!(size_of::<FFSearchResult>(), 40);
        assert_eq!(std::mem::offset_of!(FFSearchResult, path), 0);
        assert_eq!(std::mem::offset_of!(FFSearchResult, name), 8);
        assert_eq!(std::mem::offset_of!(FFSearchResult, size), 16);
        assert_eq!(std::mem::offset_of!(FFSearchResult, modified), 24);
        assert_eq!(std::mem::offset_of!(FFSearchResult, is_dir), 32);
    }

    #[test]
    fn test_abi_ff_duplicate_file_layout() {
        assert_eq!(size_of::<FFDuplicateFile>(), 40);
        assert_eq!(std::mem::offset_of!(FFDuplicateFile, id), 0);
        assert_eq!(std::mem::offset_of!(FFDuplicateFile, path), 8);
        assert_eq!(std::mem::offset_of!(FFDuplicateFile, name), 16);
        assert_eq!(std::mem::offset_of!(FFDuplicateFile, size), 24);
        assert_eq!(std::mem::offset_of!(FFDuplicateFile, modified), 32);
    }

    #[test]
    fn test_abi_ff_duplicate_group_layout() {
        assert_eq!(size_of::<FFDuplicateGroup>(), 40);
        assert_eq!(std::mem::offset_of!(FFDuplicateGroup, id), 0);
        assert_eq!(std::mem::offset_of!(FFDuplicateGroup, hash), 8);
        assert_eq!(std::mem::offset_of!(FFDuplicateGroup, size), 16);
        assert_eq!(std::mem::offset_of!(FFDuplicateGroup, files), 24);
        assert_eq!(std::mem::offset_of!(FFDuplicateGroup, file_count), 32);
    }

    #[test]
    fn test_abi_ff_rename_item_layout() {
        assert_eq!(size_of::<FFRenameItem>(), 16);
        assert_eq!(std::mem::offset_of!(FFRenameItem, original_path), 0);
        assert_eq!(std::mem::offset_of!(FFRenameItem, new_name), 8);
    }

    #[test]
    fn test_abi_ff_search_filters_layout() {
        assert_eq!(size_of::<FFSearchFilters>(), 48);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, file_types), 0);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, min_size), 8);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, max_size), 16);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, modified_after), 24);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, modified_before), 32);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, has_file_types), 40);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, has_min_size), 41);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, has_max_size), 42);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, has_modified_after), 43);
        assert_eq!(std::mem::offset_of!(FFSearchFilters, has_modified_before), 44);
    }

    #[test]
    fn test_abi_ff_search_options_layout() {
        assert_eq!(size_of::<FFSearchOptions>(), 16);
        assert_eq!(std::mem::offset_of!(FFSearchOptions, max_results), 0);
        assert_eq!(std::mem::offset_of!(FFSearchOptions, max_depth), 8);
    }
