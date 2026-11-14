// Test instrumentation; never linked into the application.
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>

static _Thread_local int enabled;
static _Thread_local int64_t allocations;
static _Thread_local int64_t allocated_bytes;

static void record_allocation(size_t count, size_t size) {
  if (!enabled) return;
  allocations++;
  if ((size != 0 && count > SIZE_MAX / size) || count * size > (uint64_t)(INT64_MAX - allocated_bytes)) {
    allocated_bytes = INT64_MAX;
  } else {
    allocated_bytes += (int64_t)(count * size);
  }
}

int64_t swift_zlib_allocation_bytes(void) { return allocated_bytes; }

int swift_zlib_allocation_calibration(void) {
  // Volatile storage prevents optimization from removing this malloc/free pair.
  void *volatile pointer = malloc(17);
  int succeeded = pointer != NULL;
  free(pointer);
  return succeeded;
}

int64_t swift_zlib_allocation_probe(int32_t start) {
  enabled = start != 0;
  int64_t result = allocations;
  if (start) {
    allocations = 0;
    allocated_bytes = 0;
  }
  return result;
}

#if defined(__APPLE__)
#include <malloc/malloc.h>

#define DYLD_INTERPOSE(replacement_function, original_function) \
  __attribute__((used)) static const struct { \
    const void *replacement; \
    const void *original; \
  } interpose_##original_function __attribute__((section("__DATA,__interpose"))) = { \
    (const void *)&replacement_function, (const void *)&original_function \
  };

static void *tracked_malloc(size_t size) {
  record_allocation(1, size);
  return malloc(size);
}

static void *tracked_calloc(size_t count, size_t size) {
  record_allocation(count, size);
  return calloc(count, size);
}

static void *tracked_realloc(void *pointer, size_t size) {
  record_allocation(1, size);
  return realloc(pointer, size);
}

static void *tracked_zone_malloc(malloc_zone_t *zone, size_t size) {
  record_allocation(1, size);
  return malloc_zone_malloc(zone, size);
}

static void *tracked_zone_calloc(malloc_zone_t *zone, size_t count, size_t size) {
  record_allocation(count, size);
  return malloc_zone_calloc(zone, count, size);
}

static void *tracked_zone_realloc(malloc_zone_t *zone, void *pointer, size_t size) {
  record_allocation(1, size);
  return malloc_zone_realloc(zone, pointer, size);
}

static void *tracked_zone_memalign(malloc_zone_t *zone, size_t alignment, size_t size) {
  record_allocation(1, size);
  return malloc_zone_memalign(zone, alignment, size);
}

static void *tracked_aligned_alloc(size_t alignment, size_t size) {
  record_allocation(1, size);
  return aligned_alloc(alignment, size);
}

static int tracked_posix_memalign(void **result, size_t alignment, size_t size) {
  record_allocation(1, size);
  return posix_memalign(result, alignment, size);
}

DYLD_INTERPOSE(tracked_malloc, malloc)
DYLD_INTERPOSE(tracked_calloc, calloc)
DYLD_INTERPOSE(tracked_realloc, realloc)
DYLD_INTERPOSE(tracked_zone_malloc, malloc_zone_malloc)
DYLD_INTERPOSE(tracked_zone_calloc, malloc_zone_calloc)
DYLD_INTERPOSE(tracked_zone_realloc, malloc_zone_realloc)
DYLD_INTERPOSE(tracked_zone_memalign, malloc_zone_memalign)
DYLD_INTERPOSE(tracked_aligned_alloc, aligned_alloc)
DYLD_INTERPOSE(tracked_posix_memalign, posix_memalign)
#else
extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);
extern void __libc_free(void *);

void *malloc(size_t size) {
  record_allocation(1, size);
  return __libc_malloc(size);
}

void *calloc(size_t count, size_t size) {
  record_allocation(count, size);
  return __libc_calloc(count, size);
}

void *realloc(void *pointer, size_t size) {
  record_allocation(1, size);
  return __libc_realloc(pointer, size);
}

void free(void *pointer) { __libc_free(pointer); }

void *memalign(size_t alignment, size_t size) {
  record_allocation(1, size);
  return __libc_memalign(alignment, size);
}

void *aligned_alloc(size_t alignment, size_t size) { return memalign(alignment, size); }

int posix_memalign(void **result, size_t alignment, size_t size) {
  if (alignment < sizeof(void *) || (alignment & (alignment - 1)) != 0) return EINVAL;
  void *pointer = memalign(alignment, size);
  if (!pointer) return ENOMEM;
  *result = pointer;
  return 0;
}
#endif
