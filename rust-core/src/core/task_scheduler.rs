//! Task scheduler with priority queue and concurrent execution.
//!
//! Supports task types: Copy, Move, Delete, Scan, Index.
//! Features:
//! - Task queue with priority levels
//! - Configurable maximum concurrent tasks
//! - Task progress tracking
//! - Persistent task history

use std::collections::{HashMap, VecDeque};
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

// ── Error codes ─────────────────────────────────────────────────────

const FF_OK: c_int = 0;
const FF_ERR_GENERIC: c_int = -1;
const FF_ERR_INVALID_PATH: c_int = -2;
const FF_ERR_IO: c_int = -3;
const FF_ERR_NOT_FOUND: c_int = -4;

// ── Task Types ──────────────────────────────────────────────────────

/// Supported task types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TaskType {
    Copy,
    Move,
    Delete,
    Scan,
    Index,
}

impl TaskType {
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "copy" => Some(TaskType::Copy),
            "move" => Some(TaskType::Move),
            "delete" => Some(TaskType::Delete),
            "scan" => Some(TaskType::Scan),
            "index" => Some(TaskType::Index),
            _ => None,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            TaskType::Copy => "Copy",
            TaskType::Move => "Move",
            TaskType::Delete => "Delete",
            TaskType::Scan => "Scan",
            TaskType::Index => "Index",
        }
    }
}

// ── Task Priority ─────────────────────────────────────────────────

/// Task priority levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TaskPriority {
    Low = 0,
    Normal = 1,
    High = 2,
    Critical = 3,
}

impl TaskPriority {
    pub fn from_i32(v: i32) -> Self {
        match v {
            3 => TaskPriority::Critical,
            2 => TaskPriority::High,
            1 => TaskPriority::Normal,
            _ => TaskPriority::Low,
        }
    }
}

// ── Task Status ───────────────────────────────────────────────────

/// Task execution status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TaskStatus {
    Pending,
    Running,
    Paused,
    Completed,
    Cancelled,
    Failed,
}

impl TaskStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            TaskStatus::Pending => "Pending",
            TaskStatus::Running => "Running",
            TaskStatus::Paused => "Paused",
            TaskStatus::Completed => "Completed",
            TaskStatus::Cancelled => "Cancelled",
            TaskStatus::Failed => "Failed",
        }
    }
}

// ── Task Definition ───────────────────────────────────────────────

/// A single task definition
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: u64,
    pub task_type: TaskType,
    pub priority: TaskPriority,
    pub status: TaskStatus,
    pub params: HashMap<String, String>,
    pub progress: f64,
    pub created_at: u64,
    pub started_at: Option<u64>,
    pub completed_at: Option<u64>,
    pub error_message: Option<String>,
}

impl Task {
    fn new(id: u64, task_type: TaskType, priority: TaskPriority, params: HashMap<String, String>) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        
        Task {
            id,
            task_type,
            priority,
            status: TaskStatus::Pending,
            params,
            progress: 0.0,
            created_at: now,
            started_at: None,
            completed_at: None,
            error_message: None,
        }
    }
}

// ── Task Scheduler ────────────────────────────────────────────────

/// Task scheduler managing queue, execution, and history
pub struct TaskScheduler {
    next_id: AtomicUsize,
    tasks: Mutex<HashMap<u64, Arc<Mutex<Task>>>>,
    queue: Mutex<VecDeque<u64>>,
    max_concurrent: Mutex<usize>,
    active_count: AtomicUsize,
    running: AtomicBool,
    history: Mutex<Vec<Task>>,
    history_limit: usize,
}

impl TaskScheduler {
    pub fn new() -> Self {
        TaskScheduler {
            next_id: AtomicUsize::new(1),
            tasks: Mutex::new(HashMap::new()),
            queue: Mutex::new(VecDeque::new()),
            max_concurrent: Mutex::new(3),
            active_count: AtomicUsize::new(0),
            running: AtomicBool::new(true),
            history: Mutex::new(Vec::new()),
            history_limit: 100,
        }
    }

    pub fn submit(&self, task_type: TaskType, priority: TaskPriority, params: HashMap<String, String>) -> u64 {
        let id = self.next_id.fetch_add(1, Ordering::SeqCst) as u64;
        let task = Task::new(id, task_type, priority, params);
        let task_arc = Arc::new(Mutex::new(task));

        {
            let mut tasks = self.tasks.lock().unwrap();
            tasks.insert(id, task_arc.clone());
        }

        {
            let mut queue = self.queue.lock().unwrap();
            queue.push_back(id);
            // Sort by priority (higher first)
            queue.make_contiguous().sort_by_key(|&task_id| {
                let tasks = self.tasks.lock().unwrap();
                if let Some(task) = tasks.get(&task_id) {
                    let task_guard = task.lock().unwrap();
                    std::cmp::Reverse(task_guard.priority as i32)
                } else {
                    std::cmp::Reverse(0)
                }
            });
        }

        // Try to start the task if we have capacity
        self.process_queue();

        id
    }

    pub fn cancel(&self, id: u64) -> bool {
        let tasks = self.tasks.lock().unwrap();
        if let Some(task_arc) = tasks.get(&id) {
            let mut task = task_arc.lock().unwrap();
            if task.status == TaskStatus::Pending || task.status == TaskStatus::Running {
                task.status = TaskStatus::Cancelled;
                return true;
            }
        }
        false
    }

    fn get_task(&self, id: u64) -> Option<Arc<Mutex<Task>>> {
        let tasks = self.tasks.lock().unwrap();
        tasks.get(&id).cloned()
    }

    pub fn list_tasks(&self) -> Vec<Task> {
        let tasks = self.tasks.lock().unwrap();
        tasks.values()
            .map(|arc| arc.lock().unwrap().clone())
            .collect()
    }

    fn get_history(&self) -> Vec<Task> {
        let history = self.history.lock().unwrap();
        history.clone()
    }

    fn set_max_concurrent(&self, max: usize) {
        let mut max_concurrent = self.max_concurrent.lock().unwrap();
        *max_concurrent = max.max(1);
    }

    fn process_queue(&self) {
        let max = *self.max_concurrent.lock().unwrap();
        let active = self.active_count.load(Ordering::SeqCst);
        
        if active >= max {
            return;
        }

        let mut queue = self.queue.lock().unwrap();
        while let Some(id) = queue.pop_front() {
            let tasks = self.tasks.lock().unwrap();
            if let Some(task_arc) = tasks.get(&id) {
                let task_clone = task_arc.clone();
                let mut task = task_clone.lock().unwrap();
                if task.status == TaskStatus::Pending {
                    task.status = TaskStatus::Running;
                    task.started_at = Some(
                        SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs()
                    );
                    drop(task);
                    drop(tasks);
                    drop(queue);

                    self.active_count.fetch_add(1, Ordering::SeqCst);

                    // Spawn a worker thread that operates on the *global*
                    // scheduler singleton. Previously this used `clone_ref`,
                    // which created an empty-shell scheduler (fresh empty
                    // HashMap/VecDeque) — the worker could neither see the
                    // task queue nor decrement the real `active_count`,
                    // leaking tasks and breaking concurrency. By calling
                    // `scheduler()` (a `&'static TaskScheduler`) inside the
                    // thread, every worker shares the same queues and
                    // counters as the caller.
                    thread::spawn(move || {
                        let s = scheduler();
                        s.execute_task(task_clone);
                        s.active_count.fetch_sub(1, Ordering::SeqCst);
                        s.process_queue();
                    });
                    return;
                }
            }
        }
    }

    fn execute_task(&self, task_arc: Arc<Mutex<Task>>) {
        // Simulate task execution
        let task_guard = task_arc.lock().unwrap();
        if task_guard.status == TaskStatus::Cancelled {
            let t = task_guard.clone();
            drop(task_guard);
            self.move_to_history(&t);
            return;
        }

        let _task_type = task_guard.task_type;
        let _task_id = task_guard.id;
        drop(task_guard);

        // Simulate work with progress updates
        for i in 1..=10 {
            let mut task = task_arc.lock().unwrap();
            if task.status == TaskStatus::Cancelled {
                let t = task.clone();
                drop(task);
                self.move_to_history(&t);
                return;
            }
            task.progress = i as f64 / 10.0;
            drop(task);
            thread::sleep(Duration::from_millis(100));
        }

        let mut task = task_arc.lock().unwrap();
        task.progress = 1.0;
        task.status = TaskStatus::Completed;
        task.completed_at = Some(
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
        );
        let task_clone = task.clone();
        drop(task);
        
        self.move_to_history(&task_clone);
    }

    fn move_to_history(&self, task: &Task) {
        let mut history = self.history.lock().unwrap();
        history.push(task.clone());
        if history.len() > self.history_limit {
            history.remove(0);
        }

        // Remove from active tasks
        let mut tasks = self.tasks.lock().unwrap();
        tasks.remove(&task.id);
    }

    fn clear_history(&self) {
        let mut history = self.history.lock().unwrap();
        history.clear();
    }
}

use std::sync::OnceLock;

static SCHEDULER: OnceLock<TaskScheduler> = OnceLock::new();

pub fn scheduler() -> &'static TaskScheduler {
    SCHEDULER.get_or_init(|| TaskScheduler::new())
}

// ── FFI Callback Types ──────────────────────────────────────────────

/// Callback for task listing
pub type FFTaskListCallback = extern "C" fn(
    id: u64,
    task_type: *const c_char,
    status: *const c_char,
    progress: f64,
    created_at: u64,
    user_data: *mut c_void,
);

/// Callback for task progress updates
pub type FFTaskProgressCallback = extern "C" fn(
    id: u64,
    progress: f64,
    status: *const c_char,
    user_data: *mut c_void,
);

// ── Public FFI API ────────────────────────────────────────────────

/// 提交一个新任务。
///
/// # Arguments
/// - `name` - NUL 结尾的 UTF-8 任务类型字符串（"Copy", "Move", "Delete", "Scan", "Index"）。
/// - `description` - NUL 结尾的 UTF-8 任务描述字符串（可为 null）。
/// - `priority` - 任务优先级（0=Low, 1=Normal, 2=High）。
/// - `out_task_id` - 输出参数，成功时指向由 Rust 分配的任务 ID 字符串，
///   调用方需使用 ff_free_string 释放。
///
/// # Returns
/// - `FF_OK` 成功。
/// - `FF_ERR_INVALID_PATH` name 或 out_task_id 为 null。
/// - `FF_ERR_GENERIC` 任务类型未知。
#[no_mangle]
pub extern "C" fn ff_task_submit(
    name: *const c_char,
    description: *const c_char,
    priority: c_int,
    out_task_id: *mut *mut c_char,
) -> c_int {
    if name.is_null() || out_task_id.is_null() {
        return FF_ERR_INVALID_PATH;
    }

    let name_str = unsafe {
        match CStr::from_ptr(name).to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        }
    };

    let task_type = match TaskType::from_str(name_str) {
        Some(t) => t,
        None => return FF_ERR_GENERIC,
    };

    let mut params = HashMap::new();
    if !description.is_null() {
        if let Ok(desc_str) = unsafe { CStr::from_ptr(description) }.to_str() {
            params.insert("description".to_string(), desc_str.to_string());
        }
    }

    let task_priority = TaskPriority::from_i32(priority);
    let id = scheduler().submit(task_type, task_priority, params);

    let id_str = CString::new(id.to_string()).unwrap_or_default();
    unsafe {
        *out_task_id = id_str.into_raw();
    }

    FF_OK
}

/// 通过任务 ID 取消任务。
///
/// # Arguments
/// - `task_id` - NUL 结尾的 UTF-8 任务 ID 字符串。
///
/// # Returns
/// - `FF_OK` 成功。
/// - `FF_ERR_INVALID_PATH` task_id 为 null 或无法解析。
/// - `FF_ERR_NOT_FOUND` 任务未找到。
#[no_mangle]
pub extern "C" fn ff_task_cancel(task_id: *const c_char) -> c_int {
    if task_id.is_null() {
        return FF_ERR_INVALID_PATH;
    }

    let id_str = unsafe {
        match CStr::from_ptr(task_id).to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        }
    };

    let id = match id_str.parse::<u64>() {
        Ok(id) => id,
        Err(_) => return FF_ERR_INVALID_PATH,
    };

    if scheduler().cancel(id) {
        FF_OK
    } else {
        FF_ERR_NOT_FOUND
    }
}

// ff_task_list 已移至 ffi/mod.rs，使用 FFTaskInfo 结构体指针回调（与 ff_ffi.h 对齐）
// ff_task_progress 已移至 ffi/mod.rs，使用输出参数式 (task_id: *const c_char, out_progress: *mut f64)

/// Get task history.
///
/// # Arguments
/// - `callback` — Called for each historical task.
/// - `user_data` — Opaque pointer passed to callback.
///
/// # Returns
/// - `FF_OK` on success.
#[no_mangle]
pub extern "C" fn ff_task_history(
    callback: FFTaskListCallback,
    user_data: *mut c_void,
) -> c_int {
    let history = scheduler().get_history();
    
    for task in history {
        let type_c = CString::new(task.task_type.as_str()).unwrap_or_default();
        let status_c = CString::new(task.status.as_str()).unwrap_or_default();
        
        callback(
            task.id,
            type_c.as_ptr(),
            status_c.as_ptr(),
            task.progress,
            task.created_at,
            user_data,
        );
    }

    FF_OK
}

/// Clear task history.
///
/// # Returns
/// - `FF_OK` on success.
#[no_mangle]
pub extern "C" fn ff_task_clear_history() -> c_int {
    scheduler().clear_history();
    FF_OK
}

// ── Tests ─────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_task_type_from_str() {
        assert_eq!(TaskType::from_str("copy"), Some(TaskType::Copy));
        assert_eq!(TaskType::from_str("Move"), Some(TaskType::Move));
        assert_eq!(TaskType::from_str("DELETE"), Some(TaskType::Delete));
        assert_eq!(TaskType::from_str("unknown"), None);
    }

    #[test]
    fn test_task_priority_from_i32() {
        assert_eq!(TaskPriority::from_i32(3), TaskPriority::Critical);
        assert_eq!(TaskPriority::from_i32(2), TaskPriority::High);
        assert_eq!(TaskPriority::from_i32(1), TaskPriority::Normal);
        assert_eq!(TaskPriority::from_i32(0), TaskPriority::Low);
    }

    #[test]
    fn test_task_scheduler_submit() {
        let scheduler = TaskScheduler::new();
        let mut params = HashMap::new();
        params.insert("source".to_string(), "/test/src".to_string());
        params.insert("destination".to_string(), "/test/dst".to_string());
        
        let id = scheduler.submit(TaskType::Copy, TaskPriority::Normal, params);
        assert!(id > 0);
        
        let tasks = scheduler.list_tasks();
        assert!(!tasks.is_empty());
    }

    #[test]
    fn test_task_scheduler_cancel() {
        let scheduler = TaskScheduler::new();
        let id = scheduler.submit(TaskType::Scan, TaskPriority::Normal, HashMap::new());
        
        assert!(scheduler.cancel(id));
        
        // After cancellation, task should be removed from active
        thread::sleep(Duration::from_millis(50));
    }
}
