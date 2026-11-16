#include <stddef.h>
#include <stdlib.h>

/* What stb_image takes memory with: C's own until the engine sets its counting ones (Core/CAllocators.zig), which it does
   before stb_image has taken anything */
static void* im_stbi_default_malloc(size_t sz) { return malloc(sz); }
static void* im_stbi_default_realloc(void* p, size_t sz) { return realloc(p, sz); }
static void im_stbi_default_free(void* p) { free(p); }
void* (*im_stbi_malloc)(size_t) = im_stbi_default_malloc;
void* (*im_stbi_realloc)(void*, size_t) = im_stbi_default_realloc;
void (*im_stbi_free)(void*) = im_stbi_default_free;

#define STBI_MALLOC(sz)       im_stbi_malloc(sz)
#define STBI_REALLOC(p,newsz) im_stbi_realloc(p,newsz)
#define STBI_FREE(p)          im_stbi_free(p)

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
