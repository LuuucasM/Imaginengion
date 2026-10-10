const std = @import("std");
const Window = @import("../Windows/Window.zig");
const AssetManager = @import("../ECSManagers/AManager.zig");
const Project = @import("Project.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const InputManager = @import("../Inputs/Input.zig");
const Renderer = @import("../Renderer/Renderer.zig");
const Program = @import("../Programs/Program.zig");
const Application = @import("../Core/Application.zig");
const Tracy = @import("Tracy.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const EngineContext = @This();
const EngineStats = @import("EngineStats.zig");
const Serializer = @import("../Serializer/Serializer.zig");

const WindowEventData = @import("../Events/WindowEventData.zig");
const WindowEventManager = @import("../Events/EventManager.zig").EventManager(WindowEventData);
pub const WindowEventCallback = WindowEventManager.EventCallback;

const EditorEventData = @import("../Events/EditorEventData.zig");
const EditorEventManager = @import("../Events/EventManager.zig").EventManager(EditorEventData);
pub const EditorEventCallback = EditorEventManager.EventCallback;

const UIManager = @import("../UI/UIManager.zig");
pub const UIEventCallback = UIManager.EventManagerT.EventCallback;
const PointerEventData = @import("../Events/PointerEventData.zig");
const PointerEventManager = @import("../Events/EventManager.zig").EventManager(PointerEventData);
pub const PointerEventCallback = PointerEventManager.EventCallback;
const PointerSystem = @import("../Pointer/PointerSystem.zig");

pub const WorldEventCallback = WorldManager.EventManagerT.EventCallback;

const MakeAllocatorVTable = @import("Allocators.zig").MakeAllocatorVTable;
const MakeIoVTable = @import("Ios.zig").MakeIoVTable;

const InternalData = struct {
    EngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
    FrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),

    // Stored rather than taken straight from MakeAllocatorVTable inside EngineAllocator/FrameAllocator,
    // because a script DLL compiles its own copy of those functions: taking the address there would give
    // the DLL's copy of the vtable. These defaults are filled in by the engine binary when the context is
    // created, so a script reading them through the context always runs the engine's allocator code, the
    // same code (and the same Tracy memory tracking) that later frees or grows that memory.
    EngineAllocVTable: *const std.mem.Allocator.VTable = &MakeAllocatorVTable(.Engine).vtable,
    FrameAllocVTable: *const std.mem.Allocator.VTable = &MakeAllocatorVTable(.Frame).vtable,

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

/// The open project, if any: its folder and the settings kept per project
mProject: Project = .{},
mAssetManager: AssetManager = .empty,
mAudioManager: AudioManager = .{},
mInputManager: InputManager = .empty,
mRenderer: Renderer = .{},

mSystemEventManager: WindowEventManager = .empty,
/// What the pointer does to entities, sent by mPointerSystem (see Events/PointerEventData.zig)
mPointerEventManager: PointerEventManager = .empty,
/// What the mouse is over and holding down, as tags and events on entities. Any entity, not just UI
mPointerSystem: PointerSystem = .empty,
/// UI land: the UI-only side of entities that have UI, and what the UI does (see UI/UIManager.zig)
mUIManager: UIManager = .empty,

mGameWorld: WorldManager = .{},
mEditorWorld: WorldManager = .{},
mSimulateWorld: WorldManager = .{},

/// Where loaded ECS object assets live (EntityAsset, SceneAsset, PlayerAsset, GCAsset), so a file is parsed once and copied from after that.
/// Nothing renders, simulates or scripts it, and it is deliberately left out of SetSyncCallbacks: nothing
/// should react to what happens in here. Not a WorldType for the same reason.
mAssetWorld: WorldManager = .{},
/// The scene every EntityAsset's entity tree is created in, since an entity has to belong to a scene
mAssetEntityScene: Scene = .uninit,

/// Where templates are opened for editing (see TmplEditPanel). Like mAssetWorld nothing runs on it, so a template's
/// scripts don't run while it is being edited, and it is its own world so an open template never shares a UUID map
/// with the loaded copy of the same file in mAssetWorld. Each open template gets a scene of its own in here.
mTmplEditWorld: WorldManager = .{},

/// What the editor's panels ask the editor to do (Events/EditorEventData.zig)
mEditorEventManager: EditorEventManager = .empty,

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

    //before anything is loaded: an entity with UI gets its element as it is read
    try self.mUIManager.Init(self.EngineAllocator());
    try self.mAssetManager.Init(self);
    try self.mRenderer.Init(self);
    try self.mAssetManager.Setup(self);
    try self.mAudioManager.Init(self);
    try self.mInputManager.Init(self.EngineAllocator());

    try self.mGameWorld.Init(self.EngineAllocator());
    try self.mEditorWorld.Init(self.EngineAllocator());
    try self.mSimulateWorld.Init(self.EngineAllocator());

    try self.mAssetWorld.Init(self.EngineAllocator());
    self.mAssetEntityScene = try self.mAssetWorld.NewScene(self, .GameLayer, .{ .bAddSceneUUID = false, .bAddSceneName = false });

    try self.mTmplEditWorld.Init(self.EngineAllocator());
}

/// Points every event manager in the engine at Program.OnEvent, the single synchronous entry
/// point. Called once from Application.Init, after both the context and the program are
/// initialized. The program is a member of Application, so it outlives every manager that points
/// at it and nothing ever needs to unregister.
pub fn SetSyncCallbacks(self: *EngineContext, program: *Program) void {
    self.mSystemEventManager.SetSyncCallback(program, Program.OnEvent);
    self.mEditorEventManager.SetSyncCallback(program, Program.OnEvent);
    self.mPointerEventManager.SetSyncCallback(program, Program.OnEvent);
    self.mUIManager.SetSyncCallback(program, Program.OnEvent);

    self.mAssetManager.SetSyncCallback(program, Program.OnEvent);
    self.mAudioManager.SetSyncCallback(program, Program.OnEvent);

    self.mGameWorld.SetSyncCallback(program, Program.OnEvent);
    self.mEditorWorld.SetSyncCallback(program, Program.OnEvent);
    self.mSimulateWorld.SetSyncCallback(program, Program.OnEvent);
}

pub fn DeInit(self: *EngineContext) void {
    const zone = Tracy.ZoneInit("EngineContext::Deinit", @src());
    defer zone.Deinit();

    self.mGameWorld.Deinit(self);
    self.mEditorWorld.Deinit(self);
    self.mSimulateWorld.Deinit(self);
    self.mTmplEditWorld.Deinit(self);

    //the objects in here hold asset handles, so they are destroyed while the asset manager is still alive.
    //the world itself is freed after the asset manager, whose object assets look at it on their way out
    self.mAssetWorld.clearAndFree(self, .All);
    //holds handles to the files objects were saved to / loaded from
    self.mSerializer.Deinit(self.EngineAllocator());

    self.mEditorEventManager.Deinit(self.EngineAllocator());
    self.mSystemEventManager.Deinit(self.EngineAllocator());
    self.mPointerEventManager.Deinit(self.EngineAllocator());
    self.mUIManager.Deinit(self);
    self.mPointerSystem.Deinit(self.EngineAllocator());

    self.mInputManager.Deinit(self.EngineAllocator());
    self.mAudioManager.Deinit(self);
    self.mAssetManager.Deinit(self);
    self.mProject.Deinit(self);
    self.mAssetWorld.Deinit(self);

    self.mRenderer.Deinit(self);

    self.mAppWindow.Deinit();

    //anything still live in the Engine pool here is a real leak and is left for Tracy to show as one
    _ = self._Internal.EngineGPA.deinit();
    Tracy.MemDiscard(.Frame);
    self._Internal.FrameArena.deinit();
}
pub fn EngineAllocator(self: *EngineContext) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = self._Internal.EngineAllocVTable,
    };
}

pub fn FrameAllocator(self: *EngineContext) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = self._Internal.FrameAllocVTable,
    };
}

pub fn Io(self: *EngineContext) std.Io {
    return .{
        .userdata = self,
        .vtable = &MakeIoVTable(.Threaded).vtable,
    };
}
