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
const EngineContext = @This();

mEngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
mEngineAllocator: std.mem.Allocator = undefined,
mFrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),
mFrameAllocator: std.mem.Allocator = undefined,

mDT: f32 = 0.0,

mAssetManager: AssetManager = .{},
mAudioManager: AudioManager = .{},
mGameEventManager: GameEventManager = .{},
mImguiEventManager: ImguiEventManager = .{},
mSystemEventManager: SystemEventManager = .{},
mInputManager: InputManager = .{},
mRenderer: Renderer = .{},

pub fn Init(self: *EngineContext, window: *Window, program: *Program, app: *Application) !void {
    self.mEngineAllocator = self.mEngineGPA.allocator();
    self.mFrameAllocator = self.mFrameArena.allocator();

    self.mAssetManager.Init(self.mEngineAllocator);
    self.mAudioManager.Init();
    self.mGameEventManager.Init(program);
    self.mImguiEventManager.Init(program);
    self.mSystemEventManager.Init(app);
    self.mInputManager.Init(self.mEngineAllocator);
    self.mRenderer.Init(window, self);
}

pub fn DeInit(self: *EngineContext) !void {
    self.mAssetManager.DeInit(self.mEngineAllocator);
    self.mAudioManager.DeInit();
    self.mGameEventManager.DeInit(self.mEngineAllocator);
    self.mImguiEventManager.DeInit();
    self.mSystemEventManager.DeInit();
    self.mInputManager.DeInit();
    self.mRenderer.DeInit();

    _ = self.mEngineGPA.deinit();
    self.mFrameArena.deinit();
}
