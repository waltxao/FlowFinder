// SAFETY(lint): C ABI 边界函数解引用 Swift 侧传入的裸指针是 FFI 固有模式，
// 调用方（Swift）无法表达 Rust 的 unsafe 语义，该 lint 对本模块属已知误报场景。
#![allow(clippy::not_unsafe_ptr_arg_deref)]
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
use std::os::raw::{c_char, c_int};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use parking_lot::Mutex;

use serde::{Deserialize, Serialize};

// ── Error codes ─────────────────────────────────────────────────────

const FF_OK: c_int = 0;
const FF_ERR_GENERIC: c_int = -1;
const FF_ERR_INVALID_PATH: c_int = -2;
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
        /// 业务解析方法（非 std::str::FromStr 实现，保持 Option/直接返回语义）。
    #[allow(clippy::should_implement_trait)]
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

/// Task scheduler managing queue, execution, and history.
///
/// `TaskScheduler` is a cheap cloneable *handle* over the shared
/// `TaskSchedulerInner` state. Worker threads capture a clone of the handle
/// of the instance that spawned them, so every worker operates on the exact
/// scheduler it belongs to — never on some other instance. (The previous
/// design captured the process-global singleton inside the worker, which let
/// a `TaskScheduler::new()` instance's workers corrupt the singleton's
/// history and `active_count`.)
#[derive(Clone)]
pub struct TaskScheduler {
    inner: Arc<TaskSchedulerInner>,
}

/// Shared state behind a [`TaskScheduler`] handle.
struct TaskSchedulerInner {
    next_id: AtomicUsize,
    tasks: Mutex<HashMap<u64, Arc<Mutex<Task>>>>,
    queue: Mutex<VecDeque<u64>>,
    max_concurrent: Mutex<usize>,
    active_count: AtomicUsize,
    history: Mutex<Vec<Task>>,
    history_limit: usize,
}

impl Default for TaskScheduler {
    fn default() -> Self {
        TaskScheduler::new()
    }
}

impl TaskScheduler {
    pub fn new() -> Self {
        TaskScheduler {
            inner: Arc::new(TaskSchedulerInner {
                next_id: AtomicUsize::new(1),
                tasks: Mutex::new(HashMap::new()),
                queue: Mutex::new(VecDeque::new()),
                max_concurrent: Mutex::new(3),
                active_count: AtomicUsize::new(0),
                history: Mutex::new(Vec::new()),
                history_limit: 100,
            }),
        }
    }

    pub fn submit(&self, task_type: TaskType, priority: TaskPriority, params: HashMap<String, String>) -> u64 {
        let id = self.inner.next_id.fetch_add(1, Ordering::SeqCst) as u64;
        let task = Task::new(id, task_type, priority, params);
        let task_arc = Arc::new(Mutex::new(task));

        {
            let mut tasks = self.inner.tasks.lock();
            tasks.insert(id, task_arc.clone());
        }

        {
            let mut queue = self.inner.queue.lock();
            queue.push_back(id);

            // P0-1 修复：排序前一次性快照所有优先级到 Vec<(u64, i32)>，
            // 避免在比较函数内反复加锁（原先 O(N log N) 次重复加锁）。
            let priorities: Vec<(u64, i32)> = {
                let tasks = self.inner.tasks.lock();
                queue
                    .iter()
                    .map(|&tid| {
                        let prio = tasks
                            .get(&tid)
                            .map(|arc| arc.lock().priority as i32)
                            .unwrap_or(0);
                        (tid, prio)
                    })
                    .collect()
            };
            // 基于快照排序，比较函数内不再加锁
            queue.make_contiguous().sort_by_key(|&task_id| {
                let prio = priorities
                    .iter()
                    .find(|(tid, _)| *tid == task_id)
                    .map(|(_, p)| *p)
                    .unwrap_or(0);
                std::cmp::Reverse(prio)
            });
        }

        // Try to start the task if we have capacity
        self.process_queue();

        id
    }

    pub fn cancel(&self, id: u64) -> bool {
        let tasks = self.inner.tasks.lock();
        if let Some(task_arc) = tasks.get(&id) {
            let mut task = task_arc.lock();
            if task.status == TaskStatus::Pending || task.status == TaskStatus::Running {
                task.status = TaskStatus::Cancelled;
                return true;
            }
        }
        false
    }

    pub fn list_tasks(&self) -> Vec<Task> {
        let tasks = self.inner.tasks.lock();
        tasks.values()
            .map(|arc| arc.lock().clone())
            .collect()
    }

    /// Returns a snapshot of the task history (completed/failed/cancelled tasks
    /// that have been moved out of the active map).
    pub fn get_history(&self) -> Vec<Task> {
        let history = self.inner.history.lock();
        history.clone()
    }

    fn process_queue(&self) {
        let max = *self.inner.max_concurrent.lock();
        let active = self.inner.active_count.load(Ordering::SeqCst);
        
        if active >= max {
            return;
        }

        let mut queue = self.inner.queue.lock();
        while let Some(id) = queue.pop_front() {
            let tasks = self.inner.tasks.lock();
            if let Some(task_arc) = tasks.get(&id) {
                let task_clone = task_arc.clone();
                let mut task = task_clone.lock();
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

                    self.inner.active_count.fetch_add(1, Ordering::SeqCst);

                    // Spawn a worker that operates on *this* scheduler
                    // instance (a clone of the handle), so its history and
                    // `active_count` stay with the instance that submitted
                    // the task. Previously the worker captured the process-
                    // global singleton: a `TaskScheduler::new()` instance's
                    // workers then wrote into the singleton's history and
                    // decremented its `active_count` (wrapping it and
                    // stalling the singleton forever).
                    //
                    // P1-7 修复：用 catch_unwind 包装 execute_task，
                    // 确保即使任务执行过程中 panic，active_count 也一定递减
                    // 且 process_queue 被调用，避免计数器泄漏导致调度器卡死。
                    let self_clone = self.clone();
                    thread::spawn(move || {
                        let _ = catch_unwind(AssertUnwindSafe(|| {
                            self_clone.execute_task(task_clone);
                        }));
                        self_clone.inner.active_count.fetch_sub(1, Ordering::SeqCst);
                        self_clone.process_queue();
                    });
                    return;
                }
            }
        }
    }

    fn execute_task(&self, task_arc: Arc<Mutex<Task>>) {
        // 模拟任务执行
        let task_guard = task_arc.lock();
        if task_guard.status == TaskStatus::Cancelled {
            let t = task_guard.clone();
            drop(task_guard);
            self.move_to_history(&t);
            return;
        }

        let _task_type = task_guard.task_type;
        let _task_id = task_guard.id;
        drop(task_guard);

        // 模拟工作并更新进度
        for i in 1..=10 {
            let mut task = task_arc.lock();
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

        let mut task = task_arc.lock();
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
        let mut history = self.inner.history.lock();
        history.push(task.clone());
        if history.len() > self.inner.history_limit {
            history.remove(0);
        }

        // 从活跃任务中移除
        let mut tasks = self.inner.tasks.lock();
        tasks.remove(&task.id);
    }

    /// 清除任务历史中已完成/失败的任务（保留 Cancelled 及仍在执行的任务）。
    pub fn clear_history(&self) {
        let mut history = self.inner.history.lock();
        history.retain(|task| {
            task.status != TaskStatus::Completed && task.status != TaskStatus::Failed
        });
    }
}

use std::sync::OnceLock;

static SCHEDULER: OnceLock<TaskScheduler> = OnceLock::new();

pub fn scheduler() -> &'static TaskScheduler {
    SCHEDULER.get_or_init(TaskScheduler::new)
}

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

    // P1-8 修复：id.to_string() 是纯数字字符串，不会包含 NUL 字节，
    // 使用 expect 而非 unwrap_or_default()——后者在失败时会静默返回空字符串，
    // 导致调用方拿到无效的任务 ID 指针。数字字符串不可能失败，此处 expect 是安全的。
    let id_str = CString::new(id.to_string())
        .expect("task id (numeric string) cannot contain NUL byte");
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
// ff_task_history 已移至 ffi/mod.rs，使用 FFTaskInfo 结构体指针回调（与 ff_ffi.h 对齐）

/// 清除任务历史中已完成/失败的任务（保留 Cancelled 及仍在执行的任务）。
///
/// # Returns
/// - `FF_OK` on success.
#[no_mangle]
pub extern "C" fn ff_task_clear_history() -> c_int {
    scheduler().clear_history();
    FF_OK
}

/// Serializes tests that mutate the *process-global* scheduler singleton
/// (`scheduler()`) — submit/cancel/history/clear_history. The singleton's
/// history is shared across test modules, so an uncoordinated
/// `ff_task_clear_history` from one test can delete a task that another test
/// has just moved into history, before its poll observes it. Test-only
/// synchronization; production code is untouched.
#[cfg(test)]
pub(crate) static TASK_TEST_LOCK: parking_lot::Mutex<()> = parking_lot::Mutex::new(());

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

    // ── Wave1 regression tests (v0.7.5 fix plan) ─────────────────────
    //
    // `ff_task_clear_history` had zero test coverage before this task.

    #[test]
    fn test_task_clear_history() {
        let s = TaskScheduler::new();
        let mut completed = Task::new(1, TaskType::Copy, TaskPriority::Normal, HashMap::new());
        completed.status = TaskStatus::Completed;
        let mut failed = Task::new(2, TaskType::Move, TaskPriority::Normal, HashMap::new());
        failed.status = TaskStatus::Failed;
        let mut cancelled = Task::new(3, TaskType::Scan, TaskPriority::Normal, HashMap::new());
        cancelled.status = TaskStatus::Cancelled;
        let mut pending = Task::new(4, TaskType::Index, TaskPriority::Normal, HashMap::new());
        pending.status = TaskStatus::Pending;

        {
            let mut history = s.inner.history.lock();
            history.push(completed);
            history.push(failed);
            history.push(cancelled.clone());
            history.push(pending);
        }

        s.clear_history();

        let history = s.get_history();
        assert_eq!(
            history.len(),
            2,
            "only Cancelled and Pending must survive clear_history, got {:?}",
            history.iter().map(|t| t.status).collect::<Vec<_>>()
        );
        assert!(
            history.iter().any(|t| t.status == TaskStatus::Cancelled),
            "Cancelled task must be retained"
        );
        assert!(
            history.iter().any(|t| t.status == TaskStatus::Pending),
            "Pending task must be retained"
        );
        assert!(
            !history.iter().any(|t| t.status == TaskStatus::Completed),
            "Completed task must be removed"
        );
        assert!(
            !history.iter().any(|t| t.status == TaskStatus::Failed),
            "Failed task must be removed"
        );
    }

    #[test]
    fn test_ff_task_clear_history_returns_ok() {
        let _guard = TASK_TEST_LOCK.lock();
        assert_eq!(ff_task_clear_history(), FF_OK);
    }
}
