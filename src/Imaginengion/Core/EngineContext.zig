const std = @import("std");
const Window = @import("../Windows/Window.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const GameEventManager = @import("../Events/GameEventManager.zig");
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const SystemEventManager = @import("../Events/SystemEventManager.zig");
const InputManager = @import("../Inputs/Input.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const Program = @import("../Programs/Program.zig");
const Application = @import("../Core/Application.zig");
const Tracy = @import("Tracy.zig");
const EngineContext = @This();

const InternalData = struct {
    EngineAllocator: std.mem.Allocator = undefined,
    FrameAllocator: std.mem.Allocator = undefined,
    EngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
    FrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),
};

mDT: f32 = 0.0,

mAssetManager: AssetManager = .{},
mAudioManager: AudioManager = .{},
mGameEventManager: GameEventManager = .{},
mImguiEventManager: ImguiEventManager = .{},
mSystemEventManager: SystemEventManager = .{},
mInputManager: InputManager = .{},
mRenderer: Renderer = .{},

_internal: InternalData = .{},

pub fn Init(self: *EngineContext, window: *Window, program: *Program, app: *Application) !void {
    const zone = Tracy.ZoneInit("EngineContext::Init", @src());
    defer zone.Deinit();

    self._internal.EngineAllocator = self._internal.EngineGPA.allocator();
    self._internal.FrameAllocator = self._internal.FrameArena.allocator();

    try self.mAssetManager.Init(self);
    try self.mRenderer.Init(window, self);
    try self.mAssetManager.Setup(self);
    try self.mAudioManager.Init();
    self.mGameEventManager.Init(program);
    self.mImguiEventManager.Init(program);
    self.mSystemEventManager.Init(app);
    self.mInputManager.Init(self.EngineAllocator());
}

pub fn DeInit(self: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EngineContext::Deinit", @src());
    defer zone.Deinit();

    try self.mAssetManager.Deinit(self);
    self.mAudioManager.Deinit();
    self.mGameEventManager.Deinit(self.EngineAllocator());
    self.mImguiEventManager.Deinit(self.EngineAllocator());
    self.mSystemEventManager.Deinit(self.EngineAllocator());
    self.mInputManager.Deinit();
    self.mRenderer.Deinit(self);

    _ = self._internal.EngineGPA.deinit();
    self._internal.FrameArena.deinit();
}

pub inline fn EngineAllocator(self: *EngineContext) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = engine_alloc,
            .resize = engine_resize,
            .remap = engine_remap,
            .free = engine_free,
        },
    };
}

pub inline fn FrameAllocator(self: *EngineContext) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = frame_alloc,
            .resize = frame_resize,
            .remap = frame_remap,
            .free = frame_free,
        },
    };
}

fn engine_alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.EngineAllocator.rawAlloc(len, alignment, ret_addr);
}

fn frame_alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.FrameAllocator.rawAlloc(len, alignment, ret_addr);
}

fn engine_resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.EngineAllocator.rawResize(memory, alignment, new_len, return_address);
}

fn frame_resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.FrameAllocator.rawResize(memory, alignment, new_len, return_address);
}

fn engine_remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.EngineAllocator.rawRemap(memory, alignment, new_len, return_address);
}

fn frame_remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.FrameAllocator.rawRemap(memory, alignment, new_len, return_address);
}

fn engine_free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.EngineAllocator.rawFree(old_memory, alignment, return_address);
}

fn frame_free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._internal.FrameAllocator.rawFree(old_memory, alignment, return_address);
}
