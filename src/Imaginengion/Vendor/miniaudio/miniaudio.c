#include <stddef.h>
#include <stdlib.h>

/* What miniaudio takes memory with: C's own until the engine sets its counting ones (Core/CAllocators.zig), which it does
   before miniaudio has taken anything */
static void* im_ma_default_malloc(size_t sz) { return malloc(sz); }
static void* im_ma_default_realloc(void* p, size_t sz) { return realloc(p, sz); }
static void im_ma_default_free(void* p) { free(p); }
void* (*im_ma_malloc)(size_t) = im_ma_default_malloc;
void* (*im_ma_realloc)(void*, size_t) = im_ma_default_realloc;
void (*im_ma_free)(void*) = im_ma_default_free;

#define MA_MALLOC(sz)     im_ma_malloc((sz))
#define MA_REALLOC(p, sz) im_ma_realloc((p), (sz))
#define MA_FREE(p)        im_ma_free((p))

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
