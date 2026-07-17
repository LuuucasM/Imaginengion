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
const EngineStats = @import("EngineStats.zig");
const Serializer = @import("../Serializer/Serializer.zig");
const ImguiManager = @import("../Imgui/Imgui.zig");

const WindowEventData = @import("../Events/WindowEventData.zig");
const WindowEventManager = @import("../Events/EventManager.zig").EventManager(WindowEventData.EventCategories, WindowEventData.Event);
pub const WindowEventCallback = WindowEventManager.EventCallback;

const ImguiEventData = @import("../Events/ImguiEventData.zig");
const ImguiEventManager = @import("../Events/EventManager.zig").EventManager(ImguiEventData.EventCategories, ImguiEventData.Event);
pub const ImguiEventCallback = ImguiEventManager.EventCallback;

const GameEventData = @import("../Events/GameEventData.zig");
const GameEventManager = @import("../Events/EventManager.zig").EventManager(GameEventData.EventCategories, GameEventData.Event);
pub const GameEventCallback = GameEventManager.EventCallback;

const MakeAllocatorVTable = @import("Allocators.zig").MakeAllocatorVTable;
const MakeIoVTable = @import("Ios.zig").MakeIoVTable;

const InternalData = struct {
    EngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
    FrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),

    ThreadedIO: std.Io.Threaded = undefined,
};

pub const IoType = enum {
    Threaded,
    Evented,
};

pub const AllocType = enum {
    Engine,
    Frame,
};

pub const WorldType = enum {
    Game,
    Editor,
    Simulate,
};

mDT: f32 = 1.0 / 60.0,

mAppWindow: Window = .{},

mAssetManager: AssetManager = .{},
mAudioManager: AudioManager = .{},
mInputManager: InputManager = .empty,
mRenderer: Renderer = .{},
mPhysicsManager: PhysicsManager = .{},

mGameEventManager: GameEventManager = .{},
mSystemEventManager: WindowEventManager = .{},

mGameWorld: SceneManager = .{},
mEditorWorld: SceneManager = .{},
mSimulateWorld: SceneManager = .{},

mImguiManager: ImguiManager = .{},
mImguiEventManager: ImguiEventManager = .{},

mSerializer: Serializer = .empty,

mEngineStats: EngineStats = .{},

mIsRunning: bool = true,

mEnviron: std.process.Environ = undefined,

_Internal: InternalData = .{},

pub fn Init(self: *EngineContext, environ: std.process.Environ) !void {
    const zone = Tracy.ZoneInit("EngineContext::Init", @src());
    defer zone.Deinit();
    self.mEnviron = environ;
    self._Internal.ThreadedIO = std.Io.Threaded.init(self._Internal.EngineGPA.allocator(), .{
        .concurrent_limit = .nothing,
        .async_limit = .nothing,
    });

    self.mEngineStats.AppTimer = .now(self._Internal.ThreadedIO.io(), .awake);

    self.mAppWindow.Init(self);

    try self.mAssetManager.Init(self);
    try self.mRenderer.Init(self);
    try self.mAssetManager.Setup(self);
    try self.mAudioManager.Init();
    try self.mInputManager.Init(self.EngineAllocator());

    try self.mPhysicsManager.Init(self.EngineAllocator());

    try self.mGameWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
    try self.mEditorWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
    try self.mSimulateWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
}

pub fn DeInit(self: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EngineContext::Deinit", @src());
    defer zone.Deinit();

    try self.mGameWorld.Deinit(self);
    try self.mEditorWorld.Deinit(self);
    try self.mSimulateWorld.Deinit(self);

    self.mGameEventManager.Deinit(self.EngineAllocator());
    self.mImguiEventManager.Deinit(self.EngineAllocator());
    self.mSystemEventManager.Deinit(self.EngineAllocator());

    self.mPhysicsManager.Deinit(self.EngineAllocator());
    self.mInputManager.Deinit(self.EngineAllocator());
    self.mAudioManager.Deinit();
    try self.mAssetManager.Deinit(self);

    self.mRenderer.Deinit(self);

    self.mAppWindow.Deinit();

    _ = self._Internal.EngineGPA.deinit();
    self._Internal.FrameArena.deinit();
}
pub fn EngineAllocator(self: *EngineContext) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &MakeAllocatorVTable(.Engine).vtable,
    };
}

pub fn FrameAllocator(self: *EngineContext) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &MakeAllocatorVTable(.Frame).vtable,
    };
}

pub fn Io(self: *EngineContext) std.Io {
    return .{
        .userdata = self,
        .vtable = &MakeIoVTable(.Threaded).vtable,
    };
}
