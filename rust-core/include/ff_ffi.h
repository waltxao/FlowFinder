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

/* ── Callback types ─────────────────────────────────────────── */
typedef void (*FFEntryCallback)(const FFEntryRef *entry, void *user_data);

/* ── Directory listing API ──────────────────────────────────── */
ff_error_t ff_list_dir(const char *path, FFEntryCallback callback, void *user_data);

/* ── File operations API ───────────────────────────────────── */
ff_error_t ff_copy_file(const char *src, const char *dst);
ff_error_t ff_move_file(const char *src, const char *dst);
ff_error_t ff_delete_file(const char *path);
ff_error_t ff_delete_dir(const char *path);
ff_error_t ff_create_dir(const char *path);
ff_error_t ff_rename(const char *src, const char *dst);

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
