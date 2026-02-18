const std = @import("std");
const Window = @import("../Windows/Window.zig");
const AssetManager = @import("../Assets/AssetManager.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const InputManager = @import("../Inputs/Input.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const Program = @import("../Programs/Program.zig");
const Application = @import("../Core/Application.zig");
const Tracy = @import("Tracy.zig");
const PhysicsManager = @import("../Physics/PhysicsManager.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const EngineContext = @This();
const EngineStats = @import("EngineStats.zig").EngineStats;

const WindowEventData = @import("../Events/WindowEventData.zig");
const WindowEventManager = @import("../Events/EventManager.zig").EventManager(WindowEventData.EventCategories, WindowEventData.Event);

const ImguiEventData = @import("../Events/ImguiEventData.zig");
const ImguiEventManager = @import("../Events/EventManager.zig").EventManager(ImguiEventData.EventCategories, ImguiEventData.Event);

const GameEventData = @import("../Events/GameEventData.zig");
const GameEventManager = @import("../Events/EventManager.zig").EventManager(GameEventData.EventCategories, GameEventData.Event);

const InternalData = struct {
    EngineAllocator: std.mem.Allocator = undefined,
    FrameAllocator: std.mem.Allocator = undefined,
    EngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
    FrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),
};

pub const WorldType = enum(u8) {
    Game,
    Editor,
    Simulate,
};

mDT: f32 = 0.0,

mAppWindow: Window = .{},

mAssetManager: AssetManager = .{},
mAudioManager: AudioManager = .{},
mInputManager: InputManager = .{},
mRenderer: Renderer = .{},
mPhysicsManager: PhysicsManager = .{},

mGameEventManager: GameEventManager = .{},
mImguiEventManager: ImguiEventManager = .{},
mSystemEventManager: WindowEventManager = .{},

mGameWorld: SceneManager = .{},
mEditorWorld: SceneManager = .{},
mSimulateWorld: SceneManager = .{},

mEngineStats: EngineStats = .{},

mIsMinimized: bool = false,

_Internal: InternalData = .{},

pub fn Init(self: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EngineContext::Init", @src());
    defer zone.Deinit();

    self.mEngineStats.AppTimer = std.time.Timer.start();

    self._Internal.EngineAllocator = self._Internal.EngineGPA.allocator();
    self._Internal.FrameAllocator = self._Internal.FrameArena.allocator();

    self.mAppWindow.Init(self);

    try self.mAssetManager.Init(self);
    try self.mRenderer.Init(self.mApplicationWindow, self);
    try self.mAssetManager.Setup(self);
    try self.mAudioManager.Init();
    self.mInputManager.Init(self.EngineAllocator());

    self.mGameWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
    self.mEditorWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
    self.mSimulateWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());

    self.mAppWindow.SetVSync(false);
}

pub fn DeInit(self: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EngineContext::Deinit", @src());
    defer zone.Deinit();

    self.mGameWorld.Deinit(self);
    self.mEditorWorld.Deinit(self);
    self.mSimulateWorld.Deinit(self);

    self.mPhysicsManager.Deinit(self.EngineAllocator());
    self.mInputManager.Deinit();
    self.mRenderer.Deinit(self);
    self.mAudioManager.Deinit();
    try self.mAssetManager.Deinit(self);

    self.mGameEventManager.Deinit(self.EngineAllocator());
    self.mImguiEventManager.Deinit(self.EngineAllocator());
    self.mSystemEventManager.Deinit(self.EngineAllocator());

    self.mAppWindow.Deinit();

    _ = self._Internal.EngineGPA.deinit();
    self._Internal.FrameArena.deinit();
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
    return engine_context._Internal.EngineAllocator.rawAlloc(len, alignment, ret_addr);
}

fn frame_alloc(context: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.FrameAllocator.rawAlloc(len, alignment, ret_addr);
}

fn engine_resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.EngineAllocator.rawResize(memory, alignment, new_len, return_address);
}

fn frame_resize(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.FrameAllocator.rawResize(memory, alignment, new_len, return_address);
}

fn engine_remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.EngineAllocator.rawRemap(memory, alignment, new_len, return_address);
}

fn frame_remap(context: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) ?[*]u8 {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.FrameAllocator.rawRemap(memory, alignment, new_len, return_address);
}

fn engine_free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.EngineAllocator.rawFree(old_memory, alignment, return_address);
}

fn frame_free(context: *anyopaque, old_memory: []u8, alignment: std.mem.Alignment, return_address: usize) void {
    const engine_context: *EngineContext = @ptrCast(@alignCast(context));
    return engine_context._Internal.FrameAllocator.rawFree(old_memory, alignment, return_address);
}
