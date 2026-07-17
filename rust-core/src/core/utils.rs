//! 通用工具函数。

/// 检查路径是否位于系统受保护目录下。
///
/// 这些目录（/System、/usr、/bin、/sbin、/etc、/var、/private）包含
/// 系统关键文件，普通文件操作不应修改它们。该函数供 scanner、bulk_read、
/// file_ops 等多处共用，避免重复实现。
pub fn is_system_protected_path(path: &str) -> bool {
    path.starts_with("/System/")
        || path.starts_with("/usr/")
        || path.starts_with("/bin/")
        || path.starts_with("/sbin/")
        || path.starts_with("/etc/")
        || path.starts_with("/var/")
        || path.starts_with("/private/")
}
