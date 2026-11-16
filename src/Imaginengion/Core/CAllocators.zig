//! The memory the C libraries take on their own, counted in the memory tree: SDL, miniaudio and stb_image each get a
//! node under the engine's (Allocators.MemoryNode), and their malloc, calloc, realloc and free are replaced by counting
//! ones (Functions) taking from a heap of their own, the same kind as the engine's Keep heap.
//! - SDL: SDL_SetMemoryFunctions
//! - miniaudio and stb_image: their MA_MALLOC/STBI_MALLOC macros call function pointers their .c files declare, the C
//!   library's own until Hook sets them
//! A library's functions can only be swapped before it has taken anything: what C's malloc gave can't be freed here. So
//! Hook is called first thing, before SDL is started (Application.Init).
//! Not counted: msdfgen, nativefiledialog and Tracy, which take memory through C++'s new or their own allocators.
const std = @import("std");
const Allocators = @import("Allocators.zig");
const MemoryNode = Allocators.MemoryNode;
const sdl = @import("CImports.zig").sdl;

pub const Library = enum { SDL, MiniAudio, StbImage };

/// A node per library. Global, since C calls the functions with nothing to find an owner by
pub var gNodes: std.EnumArray(Library, MemoryNode) = .init(.{
    .SDL = .{ .mName = "SDL" },
    .MiniAudio = .{ .mName = "miniaudio" },
    .StbImage = .{ .mName = "stb_image" },
});

/// Never freed: a library can hold memory past the engine's end, which isn't the engine's leak to report
var gHeap: Allocators.KeepHeap = .{};

/// Before each block, its size. C's malloc gives memory aligned for any type, 16 bytes on 64-bit, which this keeps
const HEADER = 16;
const ALIGNMENT: std.mem.Alignment = .@"16";

/// malloc, calloc, realloc and free for `library`, counting what it holds in its node
pub fn Functions(comptime library: Library) type {
    return struct {
        pub fn Malloc(size: usize) callconv(.c) ?*anyopaque {
            const block = gHeap.allocator().rawAlloc(HEADER + size, ALIGNMENT, @returnAddress()) orelse return null;
            @as(*usize, @ptrCast(@alignCast(block))).* = size;
            Counts().Took(.Keep, size);
            return block + HEADER;
        }

        pub fn Calloc(count: usize, size: usize) callconv(.c) ?*anyopaque {
            const bytes = std.math.mul(usize, count, size) catch return null;
            const memory: [*]u8 = @ptrCast(Malloc(bytes) orelse return null);
            @memset(memory[0..bytes], 0);
            return memory;
        }

        pub fn Realloc(memory: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
            const old = memory orelse return Malloc(size);
            const old_block = Block(old);
            const old_size = old_block.len - HEADER;
            const block = gHeap.allocator().rawRemap(old_block, ALIGNMENT, HEADER + size, @returnAddress()) orelse moved: {
                //no room where it is: a new block, what fits copied over
                const new_block = gHeap.allocator().rawAlloc(HEADER + size, ALIGNMENT, @returnAddress()) orelse return null;
                @memcpy(new_block[HEADER..][0..@min(old_size, size)], old_block[HEADER..][0..@min(old_size, size)]);
                gHeap.allocator().rawFree(old_block, ALIGNMENT, @returnAddress());
                break :moved new_block;
            };
            @as(*usize, @ptrCast(@alignCast(block))).* = size;
            Counts().Changed(.Keep, old_size, size);
            return block + HEADER;
        }

        pub fn Free(memory: ?*anyopaque) callconv(.c) void {
            const block = Block(memory orelse return);
            Counts().Gave(.Keep, block.len - HEADER);
            gHeap.allocator().rawFree(block, ALIGNMENT, @returnAddress());
        }

        fn Counts() *Allocators.Counts {
            return &gNodes.getPtr(library).mCounts;
        }

        // the whole block a pointer handed out is in, header and all
        fn Block(memory: *anyopaque) []u8 {
            const block = @as([*]u8, @ptrCast(memory)) - HEADER;
            const size = @as(*const usize, @ptrCast(@alignCast(block))).*;
            return block[0 .. HEADER + size];
        }
    };
}

const MallocFn = *const fn (usize) callconv(.c) ?*anyopaque;
const ReallocFn = *const fn (?*anyopaque, usize) callconv(.c) ?*anyopaque;
const FreeFn = *const fn (?*anyopaque) callconv(.c) void;

//declared in Vendor/miniaudio/miniaudio.c and Vendor/stb/stb.c
extern var im_ma_malloc: MallocFn;
extern var im_ma_realloc: ReallocFn;
extern var im_ma_free: FreeFn;
extern var im_stbi_malloc: MallocFn;
extern var im_stbi_realloc: ReallocFn;
extern var im_stbi_free: FreeFn;

/// From here on every library's memory is counted. First thing, before any of them has taken anything
pub fn Hook() void {
    const SDL = Functions(.SDL);
    if (!sdl.SDL_SetMemoryFunctions(SDL.Malloc, SDL.Calloc, SDL.Realloc, SDL.Free)) {
        std.log.err("SDL's memory won't be counted: {s}", .{sdl.SDL_GetError()});
    }
    const MiniAudio = Functions(.MiniAudio);
    im_ma_malloc = MiniAudio.Malloc;
    im_ma_realloc = MiniAudio.Realloc;
    im_ma_free = MiniAudio.Free;
    const StbImage = Functions(.StbImage);
    im_stbi_malloc = StbImage.Malloc;
    im_stbi_realloc = StbImage.Realloc;
    im_stbi_free = StbImage.Free;
}

/// Puts the libraries' nodes under the engine's, with what they have taken already
pub fn Attach(engine_node: *MemoryNode) void {
    for (&gNodes.values) |*node| {
        node.mEngineContext = engine_node.Context();
        node.Attach(engine_node, 0, false);
    }
}

pub fn Detach() void {
    for (&gNodes.values) |*node| node.Detach();
}
