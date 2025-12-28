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

mDT: f32 = 0.0,

mAssetManager: AssetManager = .{},
mAudioManager: AudioManager = .{},
mGameEventManager: GameEventManager = .{},
mImguiEventManager: ImguiEventManager = .{},
mSystemEventManager: SystemEventManager = .{},
mInputManager: InputManager = .{},
mRenderer: Renderer = .{},

pub fn Init(self: *EngineContext, window: *Window, engine_allocator: std.mem.Allocator, program: *Program, app: *Application) !void {
    self.mAssetManager.Init(engine_allocator);
    self.mAudioManager.Init();
    self.mGameEventManager.Init(program);
    self.mImguiEventManager.Init(program);
    self.mSystemEventManager.Init(app);
    self.mInputManager.Init(engine_allocator);
    self.mRenderer.Init(window, engine_allocator);
}

pub fn DeInit(self: *EngineContext) !void {
    self.mAssetManager.DeInit();
    self.mAudioManager.DeInit();
    self.mGameEventManager.DeInit();
    self.mImguiEventManager.DeInit();
    self.mSystemEventManager.DeInit();
    self.mInputManager.DeInit();
    self.mRenderer.DeInit();
}
