//! Bulk directory reading via macOS `getattrlistbulk(2)`.
//!
//! A single system call fetches **name + type + mtime + crtime + size** for
//! every entry in a directory, eliminating the per-entry `stat()` round-trips
//! that make `std::fs::read_dir` slow on network mounts (SMB / NFS).
//!
//! On any error the module transparently falls back to `std::fs::read_dir`
//! + `std::fs::metadata` so callers always get a usable result.
//!
//! ## Attribute layout
//!
//! `getattrlistbulk` fills a buffer with a series of variable-length records,
//! one per directory entry.  Each record starts with a `u32` length field and
//! then packs the requested attributes in ascending bit-value order.
//!
//! **Important**: despite the `getattrlist(2)` man page suggesting natural
//! alignment, empirical testing on macOS 14+ (arm64) shows that
//! `getattrlistbulk` uses **4-byte alignment for ALL attributes**, including
//! 8-byte types like `off_t` and 16-byte types like `timespec`.  Using
//! 8-byte alignment causes file size to be read from wrong offsets,
//! producing garbage values (e.g. PB-level sizes).

use std::io;
use std::path::Path;

/// A single directory entry with full metadata, obtained in one bulk read.
#[derive(Debug, Clone)]
pub struct BulkEntry {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub is_file: bool,
    pub is_symlink: bool,
    pub is_hidden: bool,
    pub extension: String,
    pub size: u64,
    /// UNIX timestamp (seconds).
    pub modified: i64,
    /// UNIX timestamp (seconds).
    pub created: i64,
    pub is_system_protected: bool,
}

/// List all entries in `path` using `getattrlistbulk(2)` on macOS, or
/// `std::fs::read_dir` + `metadata` on other platforms.
///
/// Falls back to `std::fs::read_dir` + `metadata` on any error so that
/// callers always receive a usable result, even on filesystems that do
/// not support the bulk call.
pub fn list_dir_bulk(path: &str) -> io::Result<Vec<BulkEntry>> {
    #[cfg(target_os = "macos")]
    {
        match native::list_dir_bulk_native(path) {
            Ok(entries) => Ok(entries),
            Err(e) => {
                log::debug!(
                    "getattrlistbulk failed for {:?}: {} — falling back to read_dir",
                    path,
                    e
                );
                list_dir_fallback(path)
            }
        }
    }
    #[cfg(not(target_os = "macos"))]
    {
        list_dir_fallback(path)
    }
}

// ── Native getattrlistbulk path (macOS only) ────────────────────────

#[cfg(target_os = "macos")]
mod native {
    use std::ffi::CString;
    use std::io;
    use std::path::Path;

    // ── Attribute constants (from <sys/attr.h>) ──────────────────────

    /// Must be 5 for a valid `attrlist`.
    const ATTR_BIT_MAP_COUNT: u16 = 5;

    const ATTR_CMN_RETURNED_ATTRS: u32 = 0x8000_0000;
    const ATTR_CMN_NAME: u32 = 0x0000_0001;
    const ATTR_CMN_OBJTYPE: u32 = 0x0000_0008;
    const ATTR_CMN_CRTIME: u32 = 0x0000_0200;
    const ATTR_CMN_MODTIME: u32 = 0x0000_0400;
    const ATTR_FILE_TOTALSIZE: u32 = 0x0000_0002;

    // ── Vnode types (from <sys/vnode.h>, `enum vtype`) ───────────────
    const VREG: u32 = 1; // regular file
    const VDIR: u32 = 2; // directory
    const VLNK: u32 = 5; // symbolic link

    /// I/O buffer for `getattrlistbulk` — 64 KiB, 8-byte aligned.
    const BUF_SIZE: usize = 65_536;

    #[repr(C, align(8))]
    struct AlignedBuffer([u8; BUF_SIZE]);

    pub fn list_dir_bulk_native(dir_path: &str) -> io::Result<Vec<super::BulkEntry>> {
        let c_path = CString::new(dir_path).map_err(|_| {
            io::Error::new(io::ErrorKind::InvalidInput, "path contains NUL byte")
        })?;
        let fd = unsafe { libc::open(c_path.as_ptr(), libc::O_RDONLY) };
        if fd < 0 {
            return Err(io::Error::last_os_error());
        }
        let result = list_dir_bulk_fd(fd, dir_path);
        unsafe { libc::close(fd) };
        result
    }

    fn list_dir_bulk_fd(fd: libc::c_int, dir_path: &str) -> io::Result<Vec<super::BulkEntry>> {
        let mut attrlist: libc::attrlist = unsafe { std::mem::zeroed() };
        attrlist.bitmapcount = ATTR_BIT_MAP_COUNT;
        attrlist.commonattr = ATTR_CMN_RETURNED_ATTRS
            | ATTR_CMN_NAME
            | ATTR_CMN_OBJTYPE
            | ATTR_CMN_CRTIME
            | ATTR_CMN_MODTIME;
        attrlist.fileattr = ATTR_FILE_TOTALSIZE;

        let mut buffer = AlignedBuffer([0u8; BUF_SIZE]);
        let mut entries = Vec::new();

        loop {
            let ret = unsafe {
                libc::getattrlistbulk(
                    fd,
                    &mut attrlist as *mut _ as *mut libc::c_void,
                    buffer.0.as_mut_ptr() as *mut libc::c_void,
                    BUF_SIZE,
                    0,
                )
            };

            if ret < 0 {
                return Err(io::Error::last_os_error());
            }
            if ret == 0 {
                break;
            }

            let n_entries = ret as usize;
            let mut offset = 0usize;

            for _ in 0..n_entries {
                if offset + 4 > BUF_SIZE {
                    break;
                }
                let entry_len = u32::from_ne_bytes([
                    buffer.0[offset],
                    buffer.0[offset + 1],
                    buffer.0[offset + 2],
                    buffer.0[offset + 3],
                ]) as usize;
                if entry_len == 0 || offset + entry_len > BUF_SIZE {
                    break;
                }

                let entry_slice = &buffer.0[offset..offset + entry_len];
                if let Some(e) = parse_entry(entry_slice, dir_path) {
                    entries.push(e);
                }

                offset += entry_len;
            }
        }

        Ok(entries)
    }

    /// Parse a single attribute record from the bulk buffer.
    ///
    /// Layout (all attributes use **4-byte alignment**, verified empirically):
    fn parse_entry(entry_buf: &[u8], dir_path: &str) -> Option<super::BulkEntry> {
        let mut pos = 0usize;

        let _length = read_u32(entry_buf, &mut pos)?;

        let common_returned = read_u32(entry_buf, &mut pos)?;
        let _vol_returned = read_u32(entry_buf, &mut pos)?;
        let _dir_returned = read_u32(entry_buf, &mut pos)?;
        let file_returned = read_u32(entry_buf, &mut pos)?;
        let _fork_returned = read_u32(entry_buf, &mut pos)?;

        // ── ATTR_CMN_NAME → attrreference_t { i32 offset, u32 length } ──
        let mut name = String::new();
        if common_returned & ATTR_CMN_NAME != 0 {
            let (ref_pos, data_offset, data_len) = read_attrref(entry_buf, &mut pos)?;
            let name_start = (ref_pos as isize + data_offset as isize) as usize;
            if data_len > 0
                && name_start < entry_buf.len()
                && name_start + data_len as usize <= entry_buf.len()
            {
                let name_bytes = &entry_buf[name_start..name_start + data_len as usize];
                let name_bytes = name_bytes.strip_suffix(&[0u8]).unwrap_or(name_bytes);
                name = String::from_utf8_lossy(name_bytes).into_owned();
            }
        }

        // ── ATTR_CMN_OBJTYPE → fsobj_type_t (u32) ───────────────────────
        let mut obj_type: u32 = 0;
        if common_returned & ATTR_CMN_OBJTYPE != 0 {
            obj_type = read_u32(entry_buf, &mut pos)?;
        }

        // ── ATTR_CMN_CRTIME → timespec { tv_sec: i64, tv_nsec: i64 } ────
        let mut created: i64 = 0;
        if common_returned & ATTR_CMN_CRTIME != 0 {
            created = read_timespec_sec(entry_buf, &mut pos)?;
        }

        // ── ATTR_CMN_MODTIME → timespec ─────────────────────────────────
        let mut modified: i64 = 0;
        if common_returned & ATTR_CMN_MODTIME != 0 {
            modified = read_timespec_sec(entry_buf, &mut pos)?;
        }

        // ── ATTR_FILE_TOTALSIZE → off_t (i64) — file-attribute group ────
        let mut size: u64 = 0;
        if file_returned & ATTR_FILE_TOTALSIZE != 0 {
            size = read_u64(entry_buf, &mut pos)?;
        }

        let is_dir = obj_type == VDIR;
        let is_file = obj_type == VREG;
        let is_symlink = obj_type == VLNK;
        let is_hidden = name.starts_with('.');

        let extension = Path::new(&name)
            .extension()
            .map(|e| e.to_string_lossy().into_owned())
            .unwrap_or_default();

        let full_path = Path::new(dir_path).join(&name);
        let path_str = full_path.to_string_lossy().into_owned();

        let is_system_protected = crate::core::utils::is_system_protected_path(&path_str);

        Some(super::BulkEntry {
            name,
            path: path_str,
            is_dir,
            is_file,
            is_symlink,
            is_hidden,
            extension,
            size: if is_file { size } else { 0 },
            modified,
            created,
            is_system_protected,
        })
    }

    // ── Low-level buffer readers ─────────────────────────────────────
    //
    // 经验验证（C 程序直接测试 + hex dump），getattrlistbulk 对所有属性
    // 一律使用 **4 字节对齐**，包括 u64/off_t 和 timespec 等 8/16 字节类型。
    // 不要使用 align8——会导致从错误偏移读取数据，产生 PB 级别的文件大小。

    fn read_u32(buf: &[u8], pos: &mut usize) -> Option<u32> {
        align4(pos);
        if *pos + 4 > buf.len() {
            return None;
        }
        let val = u32::from_ne_bytes(buf[*pos..*pos + 4].try_into().ok()?);
        *pos += 4;
        Some(val)
    }

    fn read_u64(buf: &[u8], pos: &mut usize) -> Option<u64> {
        align4(pos);
        if *pos + 8 > buf.len() {
            return None;
        }
        let val = u64::from_ne_bytes(buf[*pos..*pos + 8].try_into().ok()?);
        *pos += 8;
        Some(val)
    }

    /// Read an `attrreference_t` and return `(position_of_struct, data_offset, data_length)`.
    fn read_attrref(buf: &[u8], pos: &mut usize) -> Option<(usize, i32, u32)> {
        align4(pos);
        if *pos + 8 > buf.len() {
            return None;
        }
        let data_offset = i32::from_ne_bytes(buf[*pos..*pos + 4].try_into().ok()?);
        let data_length = u32::from_ne_bytes(buf[*pos + 4..*pos + 8].try_into().ok()?);
        let struct_pos = *pos;
        *pos += 8;
        Some((struct_pos, data_offset, data_length))
    }

    /// Read a `timespec` and return `tv_sec` (seconds since UNIX epoch).
    fn read_timespec_sec(buf: &[u8], pos: &mut usize) -> Option<i64> {
        align4(pos);
        if *pos + 16 > buf.len() {
            return None;
        }
        let tv_sec = i64::from_ne_bytes(buf[*pos..*pos + 8].try_into().ok()?);
        *pos += 16;
        Some(tv_sec)
    }

    fn align4(pos: &mut usize) {
        *pos = (*pos + 3) & !3;
    }
}

// ── Fallback: std::fs::read_dir + metadata (cross-platform) ─────────

fn list_dir_fallback(dir_path: &str) -> io::Result<Vec<BulkEntry>> {
    let mut entries = Vec::new();
    for entry in std::fs::read_dir(dir_path)? {
        let entry = entry?;
        let path = entry.path();
        let path_str = path.to_string_lossy().into_owned();
        let name = entry.file_name().to_string_lossy().into_owned();
        let file_type = entry.file_type()?;

        // In the fallback path we call metadata() per entry — this is the
        // original slow path, used only when getattrlistbulk is unavailable.
        let meta = entry.metadata().ok();
        let modified = meta
            .as_ref()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let created = meta
            .as_ref()
            .and_then(|m| m.created().ok())
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        let size = meta
            .as_ref()
            .map(|m| if m.is_file() { m.len() } else { 0 })
            .unwrap_or(0);

        let is_dir = file_type.is_dir();
        let is_file = file_type.is_file();
        let is_symlink = file_type.is_symlink();
        let is_hidden = name.starts_with('.');

        let extension = Path::new(&name)
            .extension()
            .map(|e| e.to_string_lossy().into_owned())
            .unwrap_or_default();

        let is_system_protected = crate::core::utils::is_system_protected_path(&path_str);

        entries.push(BulkEntry {
            name,
            path: path_str,
            is_dir,
            is_file,
            is_symlink,
            is_hidden,
            extension,
            size,
            modified,
            created,
            is_system_protected,
        });
    }
    Ok(entries)
}
