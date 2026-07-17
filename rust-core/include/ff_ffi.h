#ifndef FF_FFI_H
#define FF_FFI_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Error codes ────────────────────────────────────────────── */
typedef enum {
    FF_OK = 0,
    FF_ERR_GENERIC = -1,
    FF_ERR_INVALID_PATH = -2,
    FF_ERR_IO = -3,
    FF_ERR_NOT_FOUND = -4,
    FF_ERR_DUPLICATE = -5,
    FF_ERR_PERMISSION_DENIED = -6,
} ff_error_t;

/* ── Directory entry (C-compatible) ─────────────────────────── */
typedef struct {
    char *name;
    char *path;
    char *extension;
    bool is_dir;
    bool is_file;
    bool is_symlink;
    bool is_hidden;
    bool is_system_protected;
    uint64_t size;
    int64_t modified;
    int64_t created;
} FFEntryRef;

/* ── Duplicate file info ─────────────────────────────────── */
typedef struct {
    char *id;
    char *path;
    char *name;
    uint64_t size;
    int64_t modified;
} FFDuplicateFile;

/* ── Duplicate group info ──────────────────────────────────── */
typedef struct {
    char *id;
    char *hash;
    uint64_t size;
    FFDuplicateFile *files;
    size_t file_count;
} FFDuplicateGroup;

/* ── Search result ───────────────────────────────────────── */
typedef struct {
    char *path;
    char *name;
    uint64_t size;
    int64_t modified;
    bool is_dir;
} FFSearchResult;

/* ── Search filters ──────────────────────────────────────── */
typedef struct {
    const char *file_types;
    uint64_t min_size;
    uint64_t max_size;
    int64_t modified_after;
    int64_t modified_before;
    bool has_file_types;
    bool has_min_size;
    bool has_max_size;
    bool has_modified_after;
    bool has_modified_before;
} FFSearchFilters;

/* ── Callback types ───────────────────────────────────────── */
typedef void (*FFEntryCallback)(const FFEntryRef *entry, void *user_data);
typedef void (*FFDedupProgressCallback)(size_t scanned, size_t total, void *user_data);
typedef void (*FFDedupGroupCallback)(const FFDuplicateGroup *group, void *user_data);
typedef void (*FFSearchCallback)(const FFSearchResult *result, void *user_data);

/* ── Directory listing API ──────────────────────────────────── */
ff_error_t ff_list_dir(const char *path, FFEntryCallback callback, void *user_data);

/* ── File operations API ───────────────────────────────────── */
ff_error_t ff_copy_file(const char *src, const char *dst);
ff_error_t ff_move_file(const char *src, const char *dst);
ff_error_t ff_delete_file(const char *path);
ff_error_t ff_delete_dir(const char *path);
ff_error_t ff_create_dir(const char *path);
ff_error_t ff_rename(const char *src, const char *dst);

/* ── Duplicate file detection API ─────────────────────────── */
ff_error_t ff_scan_duplicates(const char *path,
                              FFDedupProgressCallback progress_callback,
                              FFDedupGroupCallback group_callback,
                              void *user_data);
void ff_cancel_scan(void);

/* ── File search API ───────────────────────────────────────── */
ff_error_t ff_search(const char *path, const char *query,
                       FFSearchCallback callback, void *user_data);
ff_error_t ff_search_with_filters(const char *path, const char *query,
                                   const FFSearchFilters *filters,
                                   FFSearchCallback callback, void *user_data);

/* ── QuickLook preview API ─────────────────────────────────── */
ff_error_t ff_get_preview_path(const char *path,
                                void (*callback)(const char *preview_path, void *user_data),
                                void *user_data);
char *ff_get_file_type(const char *path);

/* ── Directory Cache API ───────────────────────────────────── */
ff_error_t ff_cache_invalidate(const char *path);
ff_error_t ff_cache_get(const char *path, FFEntryCallback callback, void *user_data);
ff_error_t ff_cache_put(const char *path, const FFEntryRef *entries, size_t entry_count);

/* ── Error handling API ─────────────────────────────────────── */
char *ff_last_error(void);
void ff_free_string(char *s);

/* ── Utility API ────────────────────────────────────────────── */
char *ff_version_string(void);
uint64_t ff_get_system_memory(void);

#ifdef __cplusplus
}
#endif

#endif /* FF_FFI_H */
