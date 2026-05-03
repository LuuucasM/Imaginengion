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

const InternalData = struct {
    EngineAllocator: std.mem.Allocator = undefined,
    FrameAllocator: std.mem.Allocator = undefined,
    EngineGPA: std.heap.DebugAllocator(.{}) = std.heap.DebugAllocator(.{}).init,
    FrameArena: std.heap.ArenaAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator),
    EngineIO: std.Io.Threaded = .init_single_threaded,
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

mRandom: std.Random = undefined,

_Internal: InternalData = .{},

pub fn Init(self: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EngineContext::Init", @src());
    defer zone.Deinit();
    self.mEngineStats.AppTimer = .now(self._Internal.EngineIO.io(), .awake);

    self._Internal.EngineAllocator = self._Internal.EngineGPA.allocator();
    self._Internal.FrameAllocator = self._Internal.FrameArena.allocator();

    self.mAppWindow.Init(self);

    try self.mAssetManager.Init(self);
    try self.mRenderer.Init(self);
    try self.mAssetManager.Setup(self);
    try self.mAudioManager.Init();
    try self.mInputManager.Init(self.EngineAllocator());

    try self.mGameWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
    try self.mEditorWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());
    try self.mSimulateWorld.Init(self.mAppWindow.GetWidth(), self.mAppWindow.GetHeight(), self.EngineAllocator());

    const io_source = std.Random.IoSource{ .io = self.Io() };
    self.mRandom = io_source.interface();
}

pub fn DeInit(self: *EngineContext) !void {
    const zone = Tracy.ZoneInit("EngineContext::Deinit", @src());
    defer zone.Deinit();

    try self.mGameWorld.Deinit(self);
    try self.mEditorWorld.Deinit(self);
    try self.mSimulateWorld.Deinit(self);

    self.mPhysicsManager.Deinit(self.EngineAllocator());
    self.mInputManager.Deinit(self.EngineAllocator());
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

pub fn GenUUID(self: EngineContext) u64 {
    return self.mRandom.int(u64);
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

pub inline fn Io(self: *EngineContext) std.Io {
    return .{
        .userdata = self,
        .vtable = &.{
            .crashHandler = std.Io.noCrashHandler,

            .async = std.Io.noAsync,
            .concurrent = std.Io.failingConcurrent,
            .await = std.Io.unreachableAwait,
            .cancel = std.Io.unreachableCancel,

            .groupAsync = std.Io.noGroupAsync,
            .groupConcurrent = std.Io.failingGroupConcurrent,
            .groupAwait = std.Io.unreachableGroupAwait,
            .groupCancel = std.Io.unreachableGroupCancel,

            .recancel = std.Io.unreachableRecancel,
            .swapCancelProtection = std.Io.unreachableSwapCancelProtection,
            .checkCancel = std.Io.unreachableCheckCancel,

            .futexWait = std.Io.noFutexWait,
            .futexWaitUncancelable = std.Io.noFutexWaitUncancelable,
            .futexWake = std.Io.noFutexWake,

            .operate = std.Io.failingOperate,
            .batchAwaitAsync = std.Io.unreachableBatchAwaitAsync,
            .batchAwaitConcurrent = std.Io.unreachableBatchAwaitConcurrent,
            .batchCancel = std.Io.unreachableBatchCancel,

            .dirCreateDir = std.Io.failingDirCreateDir,
            .dirCreateDirPath = std.Io.failingDirCreateDirPath,
            .dirCreateDirPathOpen = std.Io.failingDirCreateDirPathOpen,
            .dirOpenDir = std.Io.failingDirOpenDir,
            .dirStat = std.Io.failingDirStat,
            .dirStatFile = std.Io.failingDirStatFile,
            .dirAccess = std.Io.failingDirAccess,
            .dirCreateFile = std.Io.failingDirCreateFile,
            .dirCreateFileAtomic = std.Io.failingDirCreateFileAtomic,
            .dirOpenFile = std.Io.failingDirOpenFile,
            .dirClose = std.Io.unreachableDirClose,
            .dirRead = std.Io.noDirRead,
            .dirRealPath = std.Io.failingDirRealPath,
            .dirRealPathFile = std.Io.failingDirRealPathFile,
            .dirDeleteFile = std.Io.failingDirDeleteFile,
            .dirDeleteDir = std.Io.failingDirDeleteDir,
            .dirRename = std.Io.failingDirRename,
            .dirRenamePreserve = std.Io.failingDirRenamePreserve,
            .dirSymLink = std.Io.failingDirSymLink,
            .dirReadLink = std.Io.failingDirReadLink,
            .dirSetOwner = std.Io.failingDirSetOwner,
            .dirSetFileOwner = std.Io.failingDirSetFileOwner,
            .dirSetPermissions = std.Io.failingDirSetPermissions,
            .dirSetFilePermissions = std.Io.failingDirSetFilePermissions,
            .dirSetTimestamps = std.Io.noDirSetTimestamps,
            .dirHardLink = std.Io.failingDirHardLink,

            .fileStat = std.Io.failingFileStat,
            .fileLength = std.Io.failingFileLength,
            .fileClose = std.Io.unreachableFileClose,
            .fileWritePositional = std.Io.failingFileWritePositional,
            .fileWriteFileStreaming = std.Io.noFileWriteFileStreaming,
            .fileWriteFilePositional = std.Io.noFileWriteFilePositional,
            .fileReadPositional = std.Io.failingFileReadPositional,
            .fileSeekBy = std.Io.failingFileSeekBy,
            .fileSeekTo = std.Io.failingFileSeekTo,
            .fileSync = std.Io.failingFileSync,
            .fileIsTty = std.Io.unreachableFileIsTty,
            .fileEnableAnsiEscapeCodes = std.Io.unreachableFileEnableAnsiEscapeCodes,
            .fileSupportsAnsiEscapeCodes = std.Io.unreachableFileSupportsAnsiEscapeCodes,
            .fileSetLength = std.Io.failingFileSetLength,
            .fileSetOwner = std.Io.failingFileSetOwner,
            .fileSetPermissions = std.Io.failingFileSetPermissions,
            .fileSetTimestamps = std.Io.noFileSetTimestamps,
            .fileLock = std.Io.failingFileLock,
            .fileTryLock = std.Io.failingFileTryLock,
            .fileUnlock = std.Io.unreachableFileUnlock,
            .fileDowngradeLock = std.Io.failingFileDowngradeLock,
            .fileRealPath = std.Io.failingFileRealPath,
            .fileHardLink = std.Io.failingFileHardLink,

            .fileMemoryMapCreate = std.Io.failingFileMemoryMapCreate,
            .fileMemoryMapDestroy = std.Io.unreachableFileMemoryMapDestroy,
            .fileMemoryMapSetLength = std.Io.unreachableFileMemoryMapSetLength,
            .fileMemoryMapRead = std.Io.unreachableFileMemoryMapRead,
            .fileMemoryMapWrite = std.Io.unreachableFileMemoryMapWrite,

            .processExecutableOpen = std.Io.failingProcessExecutableOpen,
            .processExecutablePath = std.Io.failingProcessExecutablePath,
            .lockStderr = std.Io.unreachableLockStderr,
            .tryLockStderr = std.Io.noTryLockStderr,
            .unlockStderr = std.Io.unreachableUnlockStderr,
            .processCurrentPath = std.Io.failingProcessCurrentPath,
            .processSetCurrentDir = std.Io.failingProcessSetCurrentDir,
            .processSetCurrentPath = std.Io.failingProcessSetCurrentPath,
            .processReplace = std.Io.failingProcessReplace,
            .processReplacePath = std.Io.failingProcessReplacePath,
            .processSpawn = std.Io.failingProcessSpawn,
            .processSpawnPath = std.Io.failingProcessSpawnPath,
            .childWait = std.Io.unreachableChildWait,
            .childKill = std.Io.unreachableChildKill,

            .progressParentFile = std.Io.failingProgressParentFile,

            .random = std.Io.noRandom,
            .randomSecure = std.Io.failingRandomSecure,

            .now = std.Io.noNow,
            .clockResolution = std.Io.failingClockResolution,
            .sleep = std.Io.noSleep,

            .netListenIp = std.Io.failingNetListenIp,
            .netAccept = std.Io.failingNetAccept,
            .netBindIp = std.Io.failingNetBindIp,
            .netConnectIp = std.Io.failingNetConnectIp,
            .netListenUnix = std.Io.failingNetListenUnix,
            .netConnectUnix = std.Io.failingNetConnectUnix,
            .netSocketCreatePair = std.Io.failingNetSocketCreatePair,
            .netSend = std.Io.failingNetSend,
            .netRead = std.Io.failingNetRead,
            .netWrite = std.Io.failingNetWrite,
            .netWriteFile = std.Io.failingNetWriteFile,
            .netClose = std.Io.unreachableNetClose,
            .netShutdown = std.Io.failingNetShutdown,
            .netInterfaceNameResolve = std.Io.failingNetInterfaceNameResolve,
            .netInterfaceName = std.Io.unreachableNetInterfaceName,
            .netLookup = std.Io.failingNetLookup,
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
