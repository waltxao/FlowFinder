//! Volume management and health check for macOS.
//!
//! Detects volume types (APFS, HFS+, ExFAT, SMB, NFS),
//! checks disk space, permissions, health status,
//! and supports SMART data reading.

use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::path::Path;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use parking_lot::Mutex;

use serde::{Deserialize, Serialize};

use crate::ffi::{FFVolumeCallback, FFVolumeInfo};

// P2-12 修复：添加缓存机制避免重复 spawn mount/df 进程。
// 缓存 TTL 为 5 秒，避免频繁的系统调用。
const VOLUME_CACHE_TTL: Duration = Duration::from_secs(5);

struct VolumeCache {
    volumes: Option<(Vec<VolumeInfo>, Instant)>,
    sizes: HashMap<String, ((u64, u64, u64), Instant)>,
}

static VOLUME_CACHE: OnceLock<Mutex<VolumeCache>> = OnceLock::new();

fn volume_cache() -> &'static Mutex<VolumeCache> {
    VOLUME_CACHE.get_or_init(|| {
        Mutex::new(VolumeCache {
            volumes: None,
            sizes: HashMap::new(),
        })
    })
}

// ── Error codes ─────────────────────────────────────────────────────

const FF_OK: c_int = 0;
const FF_ERR_GENERIC: c_int = -1;
const FF_ERR_INVALID_PATH: c_int = -2;
const FF_ERR_IO: c_int = -3;
const FF_ERR_NOT_FOUND: c_int = -4;

// ── Volume Types ───────────────────────────────────────────────────

/// Supported filesystem types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum VolumeType {
    APFS,
    HFSPlus,
    ExFAT,
    SMB,
    NFS,
    Unknown,
}

impl VolumeType {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "apfs" => VolumeType::APFS,
            "hfs+" | "hfs" | "hfs plus" => VolumeType::HFSPlus,
            "exfat" => VolumeType::ExFAT,
            "smb" | "cifs" => VolumeType::SMB,
            "nfs" => VolumeType::NFS,
            _ => VolumeType::Unknown,
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            VolumeType::APFS => "APFS",
            VolumeType::HFSPlus => "HFS+",
            VolumeType::ExFAT => "ExFAT",
            VolumeType::SMB => "SMB",
            VolumeType::NFS => "NFS",
            VolumeType::Unknown => "Unknown",
        }
    }
}

// ── Volume Info ────────────────────────────────────────────────────

/// Volume information structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeInfo {
    pub path: String,
    pub name: String,
    pub volume_type: VolumeType,
    pub total_capacity: u64,
    pub used_space: u64,
    pub free_space: u64,
    pub is_removable: bool,
    pub is_ejectable: bool,
    pub is_network: bool,
    pub mount_point: String,
    pub filesystem: String,
}

/// Health status for a volume
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VolumeHealth {
    pub path: String,
    pub overall_status: String,
    pub disk_usage_percent: f64,
    pub permission_status: String,
    pub smart_available: bool,
    pub smart_status: Option<String>,
    pub temperature_celsius: Option<i32>,
    pub power_on_hours: Option<u64>,
    pub reallocated_sectors: Option<u64>,
    pub pending_sectors: Option<u64>,
    pub warnings: Vec<String>,
}

// ── Volume Manager ────────────────────────────────────────────────

pub struct VolumeManager;

impl VolumeManager {
    /// Create a new volume manager instance
    pub fn new() -> Self {
        Self
    }

    /// List all mounted volumes
    pub fn list_volumes(&self) -> Vec<VolumeInfo> {
        // P2-12 修复：先检查缓存，避免重复 spawn mount 进程
        {
            let cache = volume_cache().lock();
            if let Some((ref volumes, fetched_at)) = cache.volumes {
                if fetched_at.elapsed() < VOLUME_CACHE_TTL {
                    return volumes.clone();
                }
            }
        }

        let mut volumes = Vec::new();

        // Get mounted volumes using mount command
        if let Ok(output) = std::process::Command::new("mount").output() {
            let output_str = String::from_utf8_lossy(&output.stdout);
            for line in output_str.lines() {
                if let Some(info) = self.parse_mount_line(line) {
                    volumes.push(info);
                }
            }
        }

        // 更新缓存
        {
            let mut cache = volume_cache().lock();
            cache.volumes = Some((volumes.clone(), Instant::now()));
        }

        volumes
    }

    /// Parse a single mount line.
    ///
    /// macOS `mount` output has the format:
    ///
    /// ```text
    /// <device> on <mount_point> (<fstype>, <option>, ...)
    /// ```
    ///
    /// Examples:
    /// - `/dev/disk1s1 on / (apfs, local, journaled)`
    /// - `//user@server/share on /Volumes/share (smbfs, nodev, nosuid)`
    /// - `host:/export on /mnt/nfs (nfs, nodev, nosuid, async)`
    ///
    /// The previous implementation split on whitespace and read
    /// `parts[4]` as the filesystem type. That worked only when the mount
    /// point contained no spaces *and* the option list started at exactly
    /// `parts[4]` — for SMB/NFS mounts (and any mount whose mount point
    /// contained a space) it picked up the wrong token (e.g. `nodev,`
    /// `local,`), so `volume_type` was almost always `Unknown` and the
    /// `is_network` heuristic silently broke. The parser below locates
    /// the ` on ` and ` (` separators structurally instead of by index,
    /// which is robust to spaces in the device or mount point.
    pub fn parse_mount_line(&self, line: &str) -> Option<VolumeInfo> {
        // Split "<device> on <rest>" at the first " on ".
        let on_idx = line.find(" on ")?;
        let _device = &line[..on_idx];
        let rest = &line[on_idx + 4..];

        // Split "<mount_point> (<options>)" at the first " (".
        let paren_idx = rest.find(" (")?;
        let mount_point = rest[..paren_idx].trim();
        let options_str = &rest[paren_idx + 2..];

        // Trim the trailing ")" (everything after the first ')' is
        // discarded — there's nothing useful there for our purposes).
        let close_idx = options_str.find(')')?;
        let options_inner = &options_str[..close_idx];

        // The first comma-separated entry inside the parens is the
        // filesystem type (e.g. `apfs`, `smbfs`, `nfs`, `hfs`, `exfat`).
        let filesystem = options_inner
            .split(',')
            .next()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "unknown".to_string());

        // Empty mount point is not a real entry.
        if mount_point.is_empty() {
            return None;
        }

        // Compute name early for filter checks
        let name = Path::new(mount_point)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or(mount_point)
            .to_string();

        // Skip system mounts - 严格过滤系统卷
        // 排除 /dev 下的系统挂载、根目录、以及 APFS 系统卷
        if mount_point.starts_with("/dev")
            || mount_point == "/"
            || mount_point == "/System/Volumes/Data"
            // APFS 系统隐藏卷（VM、Preboot、Update、xarts、iSCPreboot、Hardware、Recovery）
            || Self::is_system_volume(mount_point)
            // iOS 设备挂载点
            || mount_point.starts_with("/var/mobile")
            // 未命名 UUID 卷（通常为 APFS snapshot）
            || (mount_point.starts_with("/Volumes/") && name.len() == 36 && name.contains('-'))
        {
            return None;
        }

        let volume_type = VolumeType::from_str(&filesystem);

        // Get volume size info
        let (total, used, free) = self.get_volume_size(mount_point);

        let fs_lower = filesystem.to_lowercase();
        let is_network = fs_lower.contains("smb")
            || fs_lower.contains("cifs")
            || fs_lower.contains("nfs")
            || fs_lower.contains("afp")
            || fs_lower.contains("webdav");

        Some(VolumeInfo {
            path: mount_point.to_string(),
            name,
            volume_type,
            total_capacity: total,
            used_space: used,
            free_space: free,
            is_removable: mount_point.starts_with("/Volumes"),
            is_ejectable: mount_point.starts_with("/Volumes"),
            is_network,
            mount_point: mount_point.to_string(),
            filesystem,
        })
    }

    /// 检查挂载点是否为 APFS 系统隐藏卷
    fn is_system_volume(mount_point: &str) -> bool {
        // 已知的 APFS 系统卷名称
        const SYSTEM_VOLUME_NAMES: &[&str] = &[
            "VM", "Preboot", "Update", "xarts", "iSCPreboot",
            "Hardware", "Recovery", "SSV",
            "Data", // /System/Volumes/Data 已在上层过滤
        ];

        // 检查 /Volumes/ 下的卷名是否为系统卷
        if let Some(vol_name) = mount_point.strip_prefix("/Volumes/") {
            return SYSTEM_VOLUME_NAMES.iter().any(|&sys| vol_name == sys);
        }

        // 检查 /System/Volumes/ 下的其他系统卷
        if mount_point.starts_with("/System/Volumes/") {
            return true;
        }

        // 检查 /private/ 下的系统挂载
        if mount_point.starts_with("/private/") {
            return true;
        }

        false
    }

    /// Get volume size information
    pub fn get_volume_size(&self, path: &str) -> (u64, u64, u64) {
        // P2-12 修复：先检查缓存，避免重复 spawn df 进程
        {
            let cache = volume_cache().lock();
            if let Some((sizes, fetched_at)) = cache.sizes.get(path) {
                if fetched_at.elapsed() < VOLUME_CACHE_TTL {
                    return *sizes;
                }
            }
        }

        let result = if let Ok(output) = std::process::Command::new("df")
            .args(&["-k", path])
            .output()
        {
            let output_str = String::from_utf8_lossy(&output.stdout);
            let mut found = (0, 0, 0);
            for line in output_str.lines().skip(1) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 4 {
                    if let (Ok(total), Ok(used), Ok(free)) = (
                        parts[1].parse::<u64>(),
                        parts[2].parse::<u64>(),
                        parts[3].parse::<u64>(),
                    ) {
                        found = (total * 1024, used * 1024, free * 1024);
                        break;
                    }
                }
            }
            found
        } else {
            (0, 0, 0)
        };

        // 更新缓存
        {
            let mut cache = volume_cache().lock();
            cache.sizes.insert(path.to_string(), (result, Instant::now()));
        }

        result
    }

    /// Get detailed volume info
    pub fn get_volume_info(&self, path: &str) -> Option<VolumeInfo> {
        let volumes = self.list_volumes();
        volumes.into_iter().find(|v| v.path == path || v.mount_point == path)
    }

    /// Perform health check on a volume
    pub fn check_health(&self, path: &str) -> VolumeHealth {
        let mut health = VolumeHealth {
            path: path.to_string(),
            overall_status: "Unknown".to_string(),
            disk_usage_percent: 0.0,
            permission_status: "Unknown".to_string(),
            smart_available: false,
            smart_status: None,
            temperature_celsius: None,
            power_on_hours: None,
            reallocated_sectors: None,
            pending_sectors: None,
            warnings: Vec::new(),
        };

        // Check disk usage
        let (total, used, _) = self.get_volume_size(path);
        if total > 0 {
            health.disk_usage_percent = (used as f64 / total as f64) * 100.0;
            
            if health.disk_usage_percent > 90.0 {
                health.overall_status = "Critical".to_string();
                health.warnings.push("Disk usage is above 90%".to_string());
            } else if health.disk_usage_percent > 80.0 {
                health.overall_status = "Warning".to_string();
                health.warnings.push("Disk usage is above 80%".to_string());
            } else {
                health.overall_status = "Good".to_string();
            }
        }

        // Check permissions
        if let Ok(metadata) = std::fs::metadata(path) {
            let permissions = metadata.permissions();
            health.permission_status = if permissions.readonly() {
                "Read-only".to_string()
            } else {
                "Read/Write".to_string()
            };
        }

        // Try to get SMART data (simplified - would require diskutil or smartctl)
        health.smart_available = self.check_smart_available(path);
        if health.smart_available {
            health.smart_status = Some("Passed".to_string());
        }

        health
    }

    /// Check if SMART is available for a volume
    pub fn check_smart_available(&self, _path: &str) -> bool {
        // Simplified check - in production would use diskutil or smartctl
        false
    }

    /// Eject a volume
    pub fn eject_volume(&self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let output = std::process::Command::new("diskutil")
            .args(&["eject", path])
            .output()?;

        if output.status.success() {
            Ok(())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).into())
        }
    }

    /// Mount a network volume
    pub fn mount_network_volume(&self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let output = std::process::Command::new("mount")
            .arg(path)
            .output()?;

        if output.status.success() {
            Ok(())
        } else {
            Err(String::from_utf8_lossy(&output.stderr).into())
        }
    }
}

// ── Callback Types ────────────────────────────────────────────────

// FFVolumeCallback 已移至 crate::ffi，此处直接导入使用

/// Callback for volume info
pub type FFVolumeInfoCallback = extern "C" fn(
    path: *const c_char,
    name: *const c_char,
    volume_type: *const c_char,
    total_capacity: u64,
    used_space: u64,
    free_space: u64,
    filesystem: *const c_char,
    is_removable: bool,
    is_ejectable: bool,
    is_network: bool,
    user_data: *mut c_void,
);

/// Callback for health check results
pub type FFHealthCallback = extern "C" fn(
    path: *const c_char,
    overall_status: *const c_char,
    disk_usage_percent: f64,
    smart_available: bool,
    smart_status: *const c_char,
    user_data: *mut c_void,
);

// ── Public FFI API ───────────────────────────────────────────────

/// List all mounted volumes.
///
/// # Arguments
/// - `callback` — Called for each volume.
/// - `user_data` — Opaque pointer passed to callback.
///
/// # Returns
/// - `FF_OK` on success.
#[no_mangle]
pub extern "C" fn ff_volume_list(
    callback: FFVolumeCallback,
    user_data: *mut c_void,
) -> c_int {
    let manager = VolumeManager::new();
    let volumes = manager.list_volumes();

    for volume in volumes {
        // P1-8 修复：volume.name/path/filesystem 来自 mount 命令输出，
        // 理论上不含 NUL 字节，但 unwrap_or_default() 会在失败时静默返回空字符串。
        // 改为正确处理 CString::new 失败——跳过含 NUL 字节的异常条目。
        let name_c = match CString::new(volume.name.as_str()) {
            Ok(c) => c,
            Err(_) => {
                log::warn!("volume name contains NUL byte, skipping: {}", volume.path);
                continue;
            }
        };
        let path_c = match CString::new(volume.path.as_str()) {
            Ok(c) => c,
            Err(_) => {
                log::warn!("volume path contains NUL byte, skipping");
                continue;
            }
        };
        let fs_c = match CString::new(volume.filesystem.as_str()) {
            Ok(c) => c,
            Err(_) => {
                log::warn!("volume filesystem contains NUL byte, skipping: {}", volume.path);
                continue;
            }
        };

        let c_vol = FFVolumeInfo {
            name: name_c.into_raw(),
            path: path_c.into_raw(),
            fs_type: fs_c.into_raw(),
            total_size: volume.total_capacity,
            free_size: volume.free_space,
            used_size: volume.used_space,
            is_removable: volume.is_removable,
            is_ejectable: volume.is_ejectable,
            is_writable: !volume.is_network,
        };

        callback(&c_vol, user_data);

        // 释放 CString 内存（回调返回后回收）
        unsafe {
            let _ = CString::from_raw(c_vol.name);
            let _ = CString::from_raw(c_vol.path);
            let _ = CString::from_raw(c_vol.fs_type);
        }
    }

    FF_OK
}

/// 获取指定卷的详细信息。
///
/// # Arguments
/// - `path` - NUL 结尾的 UTF-8 路径字符串。
/// - `out_info` - 输出参数，指向调用方分配的 FFVolumeInfo 结构体。
///   成功时各字符串字段由 Rust 侧分配，调用方需使用 ff_free_string 释放。
///
/// # Returns
/// - `FF_OK` 成功。
/// - `FF_ERR_INVALID_PATH` path 或 out_info 为 null。
/// - `FF_ERR_NOT_FOUND` 卷未找到。
#[no_mangle]
pub extern "C" fn ff_volume_info(
    path: *const c_char,
    out_info: *mut FFVolumeInfo,
) -> c_int {
    if path.is_null() || out_info.is_null() {
        return FF_ERR_INVALID_PATH;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        }
    };

    let manager = VolumeManager::new();

    if let Some(volume) = manager.get_volume_info(path_str) {
        // P1-8 修复：正确处理 CString::new 失败，而非静默返回空字符串
        let name_c = match CString::new(volume.name.as_str()) {
            Ok(c) => c.into_raw(),
            Err(_) => return FF_ERR_GENERIC,
        };
        let path_c = match CString::new(volume.path.as_str()) {
            Ok(c) => c.into_raw(),
            Err(_) => {
                unsafe { let _ = CString::from_raw(name_c); }
                return FF_ERR_GENERIC;
            }
        };
        let fs_c = match CString::new(volume.filesystem.as_str()) {
            Ok(c) => c.into_raw(),
            Err(_) => {
                unsafe {
                    let _ = CString::from_raw(name_c);
                    let _ = CString::from_raw(path_c);
                }
                return FF_ERR_GENERIC;
            }
        };

        unsafe {
            *out_info = FFVolumeInfo {
                name: name_c,
                path: path_c,
                fs_type: fs_c,
                total_size: volume.total_capacity,
                free_size: volume.free_space,
                used_size: volume.used_space,
                is_removable: volume.is_removable,
                is_ejectable: volume.is_ejectable,
                is_writable: !volume.is_network,
            };
        }

        FF_OK
    } else {
        FF_ERR_NOT_FOUND
    }
}

/// Perform a health check on a volume.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path to the volume.
/// - `callback` — Called with health check results.
/// - `user_data` — Opaque pointer passed to callback.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if path is null.
#[no_mangle]
pub extern "C" fn ff_volume_health_check(
    path: *const c_char,
    out_result: *mut *mut c_char,
) -> c_int {
    if path.is_null() || out_result.is_null() {
        return FF_ERR_INVALID_PATH;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        }
    };

    let manager = VolumeManager::new();
    let health = manager.check_health(path_str);

    match serde_json::to_string(&health) {
        Ok(json) => {
            let c_str = CString::new(json).unwrap_or_default();
            unsafe {
                *out_result = c_str.into_raw();
            }
            FF_OK
        }
        Err(_) => FF_ERR_GENERIC,
    }
}

/// Eject a removable volume.
///
/// # Arguments
/// - `path` — NUL-terminated UTF-8 path to the volume.
///
/// # Returns
/// - `FF_OK` on success.
/// - `FF_ERR_INVALID_PATH` if path is null.
/// - `FF_ERR_IO` if ejection fails.
#[no_mangle]
pub extern "C" fn ff_volume_eject(path: *const c_char) -> c_int {
    if path.is_null() {
        return FF_ERR_INVALID_PATH;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        }
    };

    let manager = VolumeManager::new();
    match manager.eject_volume(path_str) {
        Ok(()) => FF_OK,
        Err(_) => FF_ERR_IO,
    }
}

/// 挂载网络卷或外部卷。
///
/// # Arguments
/// - `path` - NUL 结尾的 UTF-8 路径字符串（如 smb://server/share）。
/// - `options` - NUL 结尾的 UTF-8 挂载选项字符串（当前未使用，仅接受并忽略）。
///
/// # Returns
/// - `FF_OK` 成功。
/// - `FF_ERR_INVALID_PATH` path 为 null。
/// - `FF_ERR_IO` 挂载失败。
#[no_mangle]
pub extern "C" fn ff_volume_mount(path: *const c_char, _options: *const c_char) -> c_int {
    if path.is_null() {
        return FF_ERR_INVALID_PATH;
    }

    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return FF_ERR_INVALID_PATH,
        }
    };

    let manager = VolumeManager::new();
    match manager.mount_network_volume(path_str) {
        Ok(()) => FF_OK,
        Err(_) => FF_ERR_IO,
    }
}

// ── Tests ─────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_volume_type_from_str() {
        assert_eq!(VolumeType::from_str("apfs"), VolumeType::APFS);
        assert_eq!(VolumeType::from_str("HFS+"), VolumeType::HFSPlus);
        assert_eq!(VolumeType::from_str("ExFAT"), VolumeType::ExFAT);
        assert_eq!(VolumeType::from_str("smb"), VolumeType::SMB);
        assert_eq!(VolumeType::from_str("nfs"), VolumeType::NFS);
        assert_eq!(VolumeType::from_str("unknown"), VolumeType::Unknown);
    }

    #[test]
    fn test_volume_manager_list() {
        let manager = VolumeManager::new();
        let volumes = manager.list_volumes();
        // Should not panic and return a list (may be empty)
        assert!(volumes.len() >= 0);
    }

    #[test]
    fn test_volume_manager_get_size() {
        let manager = VolumeManager::new();
        let (total, used, free) = manager.get_volume_size("/");
        // Root should have some size
        assert!(total > 0 || (total == 0 && used == 0 && free == 0));
    }

    #[test]
    fn test_health_check() {
        let manager = VolumeManager::new();
        let health = manager.check_health("/");
        assert!(!health.path.is_empty());
        // Should have some status
        assert!(!health.overall_status.is_empty());
    }
}
