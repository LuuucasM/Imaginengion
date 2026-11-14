const std = @import("std");
const game_build_options = @import("game_build_options");

const ECSManager = @import("../ECS/ECSManager.zig");
const EngineFiles = @import("../GameBuild/EngineFiles.zig");
const ProjectWalk = @import("../GameBuild/ProjectWalk.zig");
const GroupQuery = ECSManager.GroupQuery;

const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
pub const EventData = @import("../Events/AManagerData.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const AssetComponents = @import("../ECSComponents/AComponents.zig");
const AssetComponentsList = AssetComponents.ComponentsList;
const FileMetaData = AssetComponents.FileMetaData;
const PendingDelete = AssetComponents.PendingDelete;
const LoadFailedTag = AssetComponents.LoadFailedTag;
const FileChangedTag = AssetComponents.FileChangedTag;
const AssetMetaData = AssetComponents.AssetMetaData;
const GenMetaData = AssetComponents.GenMetaData;
const Texture2D = AssetComponents.Texture2D;
const TextAsset = AssetComponents.TextAsset;
const AudioAsset = AssetComponents.AudioAsset;
const EnumAsset = AssetComponents.EnumAsset;
const EngineContext = @import("../Core/EngineContext.zig");
const Project = @import("../Core/Project.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const AManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i96 = 1_000_000_000;

pub const ECSManagerT = ECSManager.ECSManager(AssetHandle.Type, &AssetComponentsList, "AssetECS");
pub const EventManagerT = EventManager.EventManager(EventData);

const Tracy = @import("../Core/Tracy.zig");
const PlatformUtils = @import("../PlatformUtils/PlatformUtils.zig");
const FileTimeAndSize = PlatformUtils.FileTimeAndSize;

const ECSCore = @import("Manager.zig").Core;

pub const EventType = enum {
    ECSRemove,
};

pub const PathType = enum {
    Eng,
    Prj,
    Gen,
};

pub const FileSource = struct {
    rel_path: []const u8,
    path_type: PathType,
};

pub const ComputedSource = union(enum) {
    Entity: Entity,
    GameContext: GameContext,
    Player: Player,
    Scene: Scene,

    pub fn GetUUID(self: ComputedSource) u64 {
        return switch (self) {
            .Entity => |entity| entity.GetUUID(),
            .GameContext => |context| context.GetUUID(),
            .Player => |player| player.GetUUID(),
            .Scene => |scene| scene.GetUUID(),
        };
    }
};

pub const AssetErrorFlags = struct {
    pub const Reason = enum {
        FileNotFound,
    };
    pub const FileNotFound: u32 = 1 << 0;
};

pub const AssetSource = union(enum) {
    File: FileSource,
    Computed: ComputedSource,
    Default: struct {},
    pub fn GetPathType(self: AssetSource) PathType {
        return switch (self) {
            .File => |f| f.path_type,
            .Computed => PathType.Gen,
            .Default => PathType.Eng,
        };
    }
};

const InternalData = struct {
    pub const uninit: InternalData = .{
        .DefaultFileMetaData = .{},
        .DefaultTexture2D = .{},
        .DefaultTextAsset = .{},
        .DefaultAudioAsset = .{},
        .DefaultEnumAsset = .{},
    };
    pub fn Deinit(self: *InternalData, engine_context: *EngineContext) void {
        const keep_allocator = engine_context.Keep();
        self.DefaultFileMetaData.Deinit(engine_context, keep_allocator);
        self.DefaultTexture2D.Deinit(engine_context, keep_allocator);
        self.DefaultTextAsset.Deinit(engine_context, keep_allocator);
        self.DefaultAudioAsset.Deinit(engine_context, keep_allocator);
        self.DefaultEnumAsset.Deinit(engine_context, keep_allocator);
    }
    DefaultFileMetaData: FileMetaData,
    DefaultTexture2D: Texture2D,
    DefaultTextAsset: TextAsset,
    DefaultAudioAsset: AudioAsset,
    /// no values: an enum file that can't be read shows an empty dropdown
    DefaultEnumAsset: EnumAsset,
};

pub const empty: AManager = .{
    .mECSManager = .empty,
    .mEventManager = .empty,
    .mUUIDToWorldID = .empty,
    .mCWD = undefined,
    .mCWDPath = .empty,
    ._internal = .uninit,
};

const Core = ECSCore(AManager);

mECSManager: ECSManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, AssetHandle.Type),

mEventManager: EventManagerT,

mCWD: std.Io.Dir,
mCWDPath: std.ArrayList(u8),
_internal: InternalData,

pub fn Init(self: *AManager, engine_context: *EngineContext) !void {
    try self.mECSManager.Init(engine_context.Keep());

    self.mCWD = std.Io.Dir.cwd();
    const cwd_path = try self.mCWD.realPathFileAlloc(engine_context.Io(), ".", engine_context.Scratch());
    _ = try self.mCWDPath.print(engine_context.Keep(), "{s}", .{cwd_path});
}

///Setup needed to initialize "default" assets
pub fn Setup(self: *AManager, engine_context: *EngineContext) !void {
    const scratch_allocator = engine_context.Scratch();
    const io = engine_context.Io();

    //FILE META DATA =======================
    _ = try self._internal.DefaultFileMetaData.mRelPath.appendSlice(engine_context.Keep(), "default");

    //TEXTURE 2D =========================
    const texture2d_rel_path = EngineFiles.DEFAULT_TEXTURE;
    const texture2d_abs_path = try self.GetAbsPath(scratch_allocator, texture2d_rel_path, .Eng);
    const texture2d_file = try std.Io.Dir.openFileAbsolute(io, texture2d_abs_path, .{});
    defer texture2d_file.close(io);
    try self._internal.DefaultTexture2D.Init(engine_context, texture2d_abs_path, texture2d_rel_path, texture2d_file);

    //TEXT ================================
    const text_rel_path = try PackagedPath(scratch_allocator, EngineFiles.DEFAULT_FONT);
    const text_abs_path = try self.GetAbsPath(scratch_allocator, text_rel_path, .Eng);
    const text_file = try std.Io.Dir.openFileAbsolute(io, text_abs_path, .{});
    defer text_file.close(io);
    try self._internal.DefaultTextAsset.Init(engine_context, text_abs_path, text_rel_path, text_file);

    //AUDIO =================================
    const audio_rel_path = EngineFiles.DEFAULT_SOUND;
    const audio_abs_path = try self.GetAbsPath(scratch_allocator, audio_rel_path, .Eng);
    const audio_file = try std.Io.Dir.openFileAbsolute(io, audio_abs_path, .{});
    defer audio_file.close(io);
    try self._internal.DefaultAudioAsset.Init(engine_context, audio_abs_path, audio_rel_path, audio_file);
}

pub fn Deinit(self: *AManager, engine_context: *EngineContext) void {
    Core.Deinit(self, engine_context);
    self.mCWDPath.deinit(engine_context.Keep());

    self.mCWD.close(engine_context.Io());

    self._internal.Deinit(engine_context);
}

/// The file that stands for `rel_path` here: a packaged game has no font files, only the atlas made from each
/// (ProjectWalk), so a font's atlas .json is what it opens, watches and hands TextAsset
fn PackagedPath(allocator: std.mem.Allocator, rel_path: []const u8) ![]const u8 {
    if (!game_build_options.packaged_game or !ProjectWalk.IsFontFile(rel_path)) return rel_path;
    return try ProjectWalk.AtlasJsonOf(allocator, rel_path);
}

/// Whether `rel_path` is a file that isn't there to open because this is a packaged game, which has no code: its scripts
/// are compiled in (StaticScriptAsset) and it only knows an enum by name (EnumAsset). The asset still has its path
fn HasNoFile(rel_path: []const u8) bool {
    return game_build_options.packaged_game and ProjectWalk.IsCodeFile(rel_path);
}

pub fn GetAssetHandle(self: *AManager, engine_context: *EngineContext, requested_source: AssetSource) !AssetHandle {
    if (requested_source == .Default) {
        return AssetHandle{
            .mID = AssetHandle.NullObject,
            .mManager = self,
        };
    }

    var asset_source = requested_source;
    if (asset_source == .File) asset_source.File.rel_path = try PackagedPath(engine_context.Scratch(), asset_source.File.rel_path);

    const asset_hash = switch (asset_source) {
        .File => |f| blk: {
            const abs_path = try self.GetAbsPath(engine_context.Scratch(), f.rel_path, f.path_type);
            break :blk ComputePathHash(abs_path);
        },
        .Computed => |c| c.GetUUID(),
        .Default => unreachable,
    };

    const asset_id = self.GetWorldID(asset_hash);

    const keep_allocator = engine_context.Keep();

    if (asset_id) |id| {
        std.debug.assert(self.mECSManager.HasComponent(AssetMetaData, id));
        self.mECSManager.GetComponentMut(AssetMetaData, id).?.AddRef();
        return AssetHandle{ .mID = id, .mManager = self };
    } else {
        const new_asset_id = switch (asset_source) {
            .File => |f| try self.CreateAssetFile(engine_context, f),
            .Computed => try self.CreateAssetGen(engine_context),
            .Default => unreachable,
        };

        self.mECSManager.GetComponentMut(AssetMetaData, new_asset_id).?.AddRef();

        try self.AddUUID(keep_allocator, asset_hash, new_asset_id);

        return AssetHandle{ .mID = new_asset_id, .mManager = self };
    }
}

/// Takes another reference to an asset that is already loaded, for code that copies a handle it owns.
pub fn RetainAssetHandle(self: *AManager, asset_id: AssetHandle.Type) void {
    //atomic: a hook running in a batch on a worker thread retains one when it copies a component holding a handle
    self.mECSManager.GetComponentMut(AssetMetaData, asset_id).?.AddRef();
}

pub fn ReleaseAssetHandle(self: *AManager, asset_handle: *AssetHandle) void {
    const asset_meta_data = self.mECSManager.GetComponentMut(AssetMetaData, asset_handle.mID).?;
    asset_meta_data.DropRef();
    asset_handle.mID = AssetHandle.NullObject;
}

/// Whether an asset is read in right now: not before the first GetAsset, nor between a change to its file unloading it
/// and the next GetAsset reading it again
pub fn IsLoaded(self: *AManager, comptime asset_type: type, asset_id: AssetHandle.Type) bool {
    return self.mECSManager.IsActiveEntity(asset_id) and self.mECSManager.HasComponent(asset_type, asset_id);
}

/// Whether any asset's file changed last frame (see FileChangedTag)
pub fn AnyFileChanged(self: *AManager) bool {
    return self.mECSManager.NumWithComponent(FileChangedTag) != 0;
}

/// Whether this asset's file changed last frame (see FileChangedTag)
pub fn FileChanged(self: *AManager, asset_id: AssetHandle.Type) bool {
    return self.mECSManager.IsActiveEntity(asset_id) and self.mECSManager.HasComponent(FileChangedTag, asset_id);
}

/// The asset if it is loaded, never loading it: for something that only has work to do if it is (a script child giving
/// back its variables)
pub fn GetLoadedAsset(self: *AManager, comptime asset_type: type, asset_id: AssetHandle.Type) ?*asset_type {
    _ValidateAssetType(asset_type);
    if (!self.mECSManager.IsActiveEntity(asset_id)) return null;
    return self.mECSManager.GetComponentMut(asset_type, asset_id);
}

pub fn GetAsset(self: *AManager, engine_context: *EngineContext, comptime asset_type: type, asset_id: AssetHandle.Type) !*asset_type {
    _ValidateAssetType(asset_type);

    if (self.mECSManager.IsActiveEntity(asset_id)) {
        if (self.mECSManager.GetComponentMut(asset_type, asset_id)) |asset| {
            return asset;
        } else if (self.mECSManager.HasComponent(LoadFailedTag, asset_id)) {
            //it failed last time and the file has not changed since, so it would only fail again
            return try self.GetDefaultAsset(asset_type);
        } else {
            //a load changes the asset manager, which a hook speculating in a batch mustn't: it runs again on its own
            if (engine_context.mTransactions.RefuseSpeculative()) |err| return err;
            engine_context.mTransactions.CheckMainThread("Loading an asset");

            //only the load is zoned: the hit path above is a lookup that runs for every drawn shape
            const zone = Tracy.ZoneInit("AssetManager::LoadAsset", @src());
            defer zone.Deinit();

            const file_data = self.mECSManager.GetComponent(FileMetaData, asset_id).?;
            zone.Text(file_data.mRelPath.items);
            //TODO: maybe a check to ensure rel path is valid?

            const abs_path = try self.GetAbsPath(engine_context.Scratch(), file_data.mRelPath.items, file_data.mPathType);

            //a script compiled in has no file, and StaticScriptAsset doesn't read one
            const compiled_in = game_build_options.packaged_game and asset_type == AssetComponents.ScriptAsset;
            const asset_file: std.Io.File = if (compiled_in) undefined else try self.OpenFile(engine_context, file_data.mRelPath.items, file_data.mPathType);
            defer if (!compiled_in) self.CloseFile(engine_context.Io(), asset_file);

            var asset_component = asset_type{};
            asset_component.Init(engine_context, abs_path, file_data.mRelPath.items, asset_file) catch |err| {
                if (err == error.AssetInitFailed) {
                    std.log.err("Failed To initialize asset {s} for asset type {s}\n", .{ abs_path, @typeName(asset_type) });
                    _ = try self.mECSManager.AddComponentSync(engine_context, asset_id, LoadFailedTag{});
                    return try self.GetDefaultAsset(asset_type);
                } else return err;
            };

            return self.mECSManager.AddComponentSync(engine_context, asset_id, asset_component);
        }
    } else {
        return try self.GetDefaultAsset(asset_type);
    }
}

pub fn GetFileMetaData(self: *AManager, id: AssetHandle.Type) *FileMetaData {
    if (self.mECSManager.IsActiveEntity(id)) {
        return self.mECSManager.GetComponentMut(FileMetaData, id).?;
    } else {
        return &self._internal.DefaultFileMetaData;
    }
}

pub fn OnUpdate(self: *AManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AssetManager::OnUpdate", @src());
    defer zone.Deinit();

    const scratch_allocator = engine_context.Scratch();

    //the files that changed last frame have had their frame to be caught up with
    try self.ClearFileChanged(engine_context);

    //check through all the assets we currently have to see if they are still valid/need to be updated
    const group = try self.mECSManager.GetGroup(scratch_allocator, .{ .Component = FileMetaData });
    zone.Value(group.items.len);
    Tracy.Plot("Assets/Tracked Files", .{ .color = 0x607D8B }, group.items.len);
    Tracy.Plot("Assets/Pending Delete", .{ .color = 0x9E9E9E }, self.mECSManager.NumWithComponent(PendingDelete));
    //every file stat'ed at once, one task per asset on the job Io: a stat is mostly waiting on the OS. Each task only
    //reads its own path and writes its own result, so they share nothing; everything that changes the asset ECS waits
    //for the loop after, on this thread
    const checks = try scratch_allocator.alloc(FileCheck, group.items.len);
    for (group.items, checks) |asset_id, *check| {
        const file_data = self.mECSManager.GetComponent(FileMetaData, asset_id).?;
        check.* = .{ .mRelPath = file_data.mRelPath.items, .mPathType = file_data.mPathType };
    }
    const io = engine_context.Io();
    var stats: std.Io.Group = .init;
    for (checks) |*check| stats.async(io, StatFile, .{ self, engine_context, check });
    try stats.await(io);

    for (group.items, checks) |asset_id, check| {
        const file_data = self.mECSManager.GetComponentMut(FileMetaData, asset_id).?;

        //the stat tells us the file still exists, and costs no handle (see StatTimeAndSize)
        const stat = check.mResult catch |err| {
            if (err == error.FileNotFound) {
                try self.MarkForDelete(engine_context, asset_id, .FileNotFound);
                continue;
            }
            return err;
        };

        //the stat worked, so the file is there: anything that marked it for deletion while it was
        //missing no longer applies
        try self.UnmarkForDelete(engine_context, asset_id);

        //an edit that leaves mtime and size untouched is not detected. Catching that would mean
        //hashing every asset's full contents every frame, which is not worth it here.
        if (file_data.mLastModified.nanoseconds == stat.mtime.nanoseconds and file_data.mSize == stat.size) continue;

        const file = self.OpenFile(engine_context, file_data.mRelPath.items, file_data.mPathType) catch |err| {
            if (err == error.FileNotFound) {
                try self.MarkForDelete(engine_context, asset_id, .FileNotFound);
                continue;
            }
            return err;
        };
        defer self.CloseFile(engine_context.Io(), file);

        if (!try file_data.Eql(engine_context, file, stat)) {
            try file_data.UpdateMetaData(engine_context, file, stat);
            try self.mEventManager.Insert(engine_context.Keep(), .EndOfFrame, .{ .FileUpdate = .{ .mAssetID = asset_id } });
        }
    }

    //asked of the ECS rather than kept in a side map, so the mark cannot outlive the asset: a
    //destroyed asset takes its PendingDelete with it instead of leaving an entry that re-queues
    //ToDestroyAsset every frame against a dead (or worse, recycled) id.
    //Queried after the loop above so a mark made this frame is already in it, as it was before.
    const pending = try self.mECSManager.GetGroup(scratch_allocator, .{ .Component = PendingDelete });
    const t1 = std.Io.Timestamp.now(engine_context.Io(), .awake);
    for (pending.items) |asset_id| {
        const pending_delete = self.mECSManager.GetComponent(PendingDelete, asset_id).?;

        //TODO: here I can add different things to see if I can possibly recover the file based on its different reasons

        const duration = pending_delete.mTime.durationTo(t1);
        const ns = duration.toNanoseconds();
        if (ns > ASSET_DELETE_TIMEOUT_NS) {
            try self.mEventManager.Insert(engine_context.Keep(), .EndOfFrame, .{ .ToDestroyAsset = .{ .mAssetID = asset_id } });
        }
    }
}

/// One tracked file's stat in OnUpdate: where it is, copied out of its FileMetaData before the stats start, and what
/// its stat found
const FileCheck = struct {
    mRelPath: []const u8,
    mPathType: PathType,
    mResult: anyerror!FileTimeAndSize = error.NotChecked,
};

/// One task of OnUpdate's stats
fn StatFile(self: *AManager, engine_context: *EngineContext, check: *FileCheck) void {
    check.mResult = self.OpenFileStats(engine_context, check.mRelPath, check.mPathType);
}

/// Takes every FileChangedTag off, done at the start of OnUpdate so each lasts the one frame after its change
pub fn ClearFileChanged(self: *AManager, engine_context: *EngineContext) !void {
    if (!self.AnyFileChanged()) return;
    const changed = try self.mECSManager.GetGroup(engine_context.Scratch(), .{ .Component = FileChangedTag });
    for (changed.items) |asset_id| {
        //a tag has no value to move, so it is safe to take off now
        try self.mECSManager.RemoveComponentSync(engine_context, asset_id, ECSManagerT.ComponentInd(FileChangedTag));
    }
}

/// The project .Prj paths are relative to. Reached through the EngineContext this manager lives in, since the path
/// helpers are called without one
fn GetProject(self: *AManager) *const Project {
    const engine_context: *EngineContext = @alignCast(@fieldParentPtr("mAssetManager", self));
    return &engine_context.mProject;
}

pub fn OpenFileStats(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !FileTimeAndSize {
    const zone = Tracy.ZoneInit("AssetManager::OpenFileStats", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => return try PlatformUtils.StatTimeAndSize(engine_context.Io(), self.mCWD, rel_path),
        .Prj => return try PlatformUtils.StatTimeAndSize(engine_context.Io(), engine_context.mProject.GetDirectory(), rel_path),
        .Gen => return error.NoFileToOpen,
    }
}

pub fn OpenFile(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File {
    const zone = Tracy.ZoneInit("AssetManager::OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try self.mCWD.openFile(engine_context.Io(), rel_path, .{}),
        .Prj => return try engine_context.mProject.GetDirectory().openFile(engine_context.Io(), rel_path, .{}),
        .Gen => unreachable,
    }
}

pub fn CloseFile(_: *AManager, io: std.Io, file: std.Io.File) void {
    const zone = Tracy.ZoneInit("AssetManager::CloseFile", @src());
    defer zone.Deinit();
    file.close(io);
}

pub fn GetFileStats(_: *AManager, engine_context: *EngineContext, file: std.Io.File) !std.Io.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager::GetFileStats", @src());
    defer zone.Deinit();
    return try file.stat(engine_context.Io());
}

pub fn GetAbsPath(self: *AManager, allocator: std.mem.Allocator, rel_path: []const u8, path_type: PathType) ![]const u8 {
    switch (path_type) {
        .Eng => {
            return try std.fs.path.join(allocator, &[_][]const u8{ self.mCWDPath.items, rel_path });
        },
        .Prj => {
            return try self.GetProject().GetAbsPath(allocator, rel_path);
        },
        .Gen => unreachable,
    }
}

/// Which root an absolute path (from a file dialog) is kept by: the open project's if it is inside it, else the
/// engine's
pub fn PathTypeOf(self: *AManager, abs_path: []const u8) PathType {
    const project = self.GetProject();
    return if (project.IsOpen() and std.mem.startsWith(u8, abs_path, project.mPath.items)) .Prj else .Eng;
}

pub fn GetRelPath(self: *AManager, abs_path: []const u8, path_type: PathType) []const u8 {
    return switch (path_type) {
        .Eng => abs_path[self.mCWDPath.items.len + 1 ..],
        .Prj => self.GetProject().GetRelPath(abs_path),
        .Gen => unreachable,
    };
}

//From general managers
pub const GetGroup = Core.GetGroup;

pub const SetSyncCallback = Core.SetSyncCallback;

pub const IsActiveObj = Core.IsActiveObj;

pub fn clearAndFree(self: *AManager, engine_context: *EngineContext) void {
    Core.clearAndFree(self, engine_context);
}

pub fn ProcessEvents(self: *AManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: *std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        var callback = EventManagerT.EventCallback{
            .mCtx = self,
            .mCallbackFn = struct {
                fn thunk(ctx: *anyopaque, ec: *EngineContext, event: *const event_data.EventT) anyerror!EventResult {
                    return @as(*AManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event.*);
                }
            }.thunk,
        };
        //the node is ours, but the list belongs to the caller, so unlink again on the way out
        callback_list.append(&callback.mNode);
        defer callback_list.remove(&callback.mNode);

        try self.mEventManager.ProcessCategory(event_category, engine_context, callback_list.*);
        self.mEventManager.ClearCategory(engine_context.Keep(), event_category, .ClearRetainingCapacity);
    } else {
        std.log.err("AManager.ProcessEvents does not currently handle processing events of type {s}", .{@typeName(event_data)});
    }
}

/// Runs the asset destroys queued this frame: the manager events hand each dead asset to the ECS
/// as a destroy, then the ECS events actually free it.
pub fn ProcessDestroyedAssets(self: *AManager, engine_context: *EngineContext) !void {
    var callback_list: std.DoublyLinkedList = .{};
    try self.ProcessEvents(EventData, .EndOfFrame, engine_context, &callback_list);
    try self.mECSManager.ProcessEvents(engine_context);
}

pub fn OnManagerEvents(self: *AManager, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventManager.EventResult {
    switch (event) {
        .FileUpdate => |e| {
            inline for (AssetComponents.FileUpdateList) |comp_type| {
                if (self.mECSManager.HasComponent(comp_type, e.mAssetID)) {
                    try self.mECSManager.RemoveComponent(engine_context, e.mAssetID, ECSManagerT.ComponentInd(comp_type));
                }
            }
            //new contents get a fresh try
            if (self.mECSManager.HasComponent(LoadFailedTag, e.mAssetID)) {
                try self.mECSManager.RemoveComponent(engine_context, e.mAssetID, ECSManagerT.ComponentInd(LoadFailedTag));
            }
            //for the next frame, so what was built from the old contents can catch up (see FileChangedTag)
            if (!self.mECSManager.HasComponent(FileChangedTag, e.mAssetID)) {
                _ = try self.mECSManager.AddComponentSync(engine_context, e.mAssetID, FileChangedTag{});
            }
        },
        .ToDestroyAsset => |e| {
            const file_data = self.mECSManager.GetComponent(FileMetaData, e.mAssetID).?;
            const abs_path = try self.GetAbsPath(engine_context.Scratch(), file_data.mRelPath.items, file_data.mPathType);
            const asset_hash = ComputePathHash(abs_path);
            self.RemoveUUID(asset_hash);
            try self.mECSManager.DestroyEntity(engine_context, e.mAssetID);
        },
        .Default => unreachable,
    }
    return .Continue;
}

pub const AddUUID = Core.AddUUID;

pub const RemoveUUID = Core.RemoveUUID;

pub const GetWorldID = Core.GetWorldID;

fn CreateAssetFile(self: *AManager, engine_context: *EngineContext, file_source: FileSource) !AssetHandle.Type {
    const zone = Tracy.ZoneInit("AssetManager::CreateAssetFile", @src());
    defer zone.Deinit();

    const keep_allocator = engine_context.Keep();

    const new_asset_id = try self.mECSManager.CreateEntity(keep_allocator);

    _ = try self.mECSManager.AddComponentSync(engine_context, new_asset_id, AssetMetaData{ .mRefs = 0 });

    var file_meta_data = FileMetaData{
        .mPathType = file_source.path_type,
    };
    _ = try file_meta_data.mRelPath.print(keep_allocator, "{s}", .{file_source.rel_path});
    const new_file_data = try self.mECSManager.AddComponentSync(engine_context, new_asset_id, file_meta_data);
    if (HasNoFile(file_source.rel_path)) return new_asset_id;

    const file = try self.OpenFile(engine_context, file_source.rel_path, file_source.path_type);
    defer self.CloseFile(engine_context.Io(), file);
    //nothing watches a packaged game's files (GameProgram never calls OnUpdate), so it only has to be there
    if (game_build_options.packaged_game) return new_asset_id;
    const fstats = try file.stat(engine_context.Io());

    try new_file_data.UpdateMetaData(engine_context, file, .{ .mtime = fstats.mtime, .size = fstats.size });

    return new_asset_id;
}

fn CreateAssetGen(self: *AManager, engine_context: *EngineContext) !AssetHandle.Type {
    const zone = Tracy.ZoneInit("AssetManager::CreateAssetGen", @src());
    defer zone.Deinit();

    const new_asset_id = try self.mECSManager.CreateEntity(engine_context.Keep());

    _ = try self.mECSManager.AddComponentSync(engine_context, new_asset_id, AssetMetaData{ .mRefs = 0 });
    _ = try self.mECSManager.AddComponentSync(engine_context, new_asset_id, GenMetaData{});

    return new_asset_id;
}

fn ComputePathHash(path: []const u8) u64 {
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(path);
    return hasher.final();
}

fn GetDefaultAsset(self: *AManager, asset_type: type) !*asset_type {
    if (asset_type == FileMetaData) {
        return &self._internal.DefaultFileMetaData;
    } else if (asset_type == Texture2D) {
        return &self._internal.DefaultTexture2D;
    } else if (asset_type == TextAsset) {
        return &self._internal.DefaultTextAsset;
    } else if (asset_type == AudioAsset) {
        return &self._internal.DefaultAudioAsset;
    } else if (asset_type == EnumAsset) {
        return &self._internal.DefaultEnumAsset;
    } else {
        //not every asset type has a stand-in; those just fail the load instead
        std.log.err("No default asset available for asset type {s}", .{@typeName(asset_type)});
        return error.NoDefaultAsset;
    }
}

fn MarkForDelete(self: *AManager, engine_context: *EngineContext, asset_id: AssetHandle.Type, reason: AssetErrorFlags.Reason) !void {
    const error_flags = switch (reason) {
        .FileNotFound => AssetErrorFlags.FileNotFound,
    };

    //already marked: add the reason and leave mTime alone, so the grace period runs from the first
    //thing that went wrong rather than restarting on every later one
    if (self.mECSManager.GetComponentMut(PendingDelete, asset_id)) |pending_delete| {
        pending_delete.mReason |= error_flags;
        return;
    }

    _ = try self.mECSManager.AddComponentSync(engine_context, asset_id, PendingDelete{
        .mReason = error_flags,
        .mTime = std.Io.Timestamp.now(engine_context.Io(), .awake),
    });
}

/// Called when an asset's file turns out to be fine after all, so a file that only briefly went
/// missing (an editor saving by rename, say) is not destroyed a second later.
fn UnmarkForDelete(self: *AManager, engine_context: *EngineContext, asset_id: AssetHandle.Type) !void {
    if (!self.mECSManager.HasComponent(PendingDelete, asset_id)) return;
    try self.mECSManager.RemoveComponentSync(engine_context, asset_id, ECSManagerT.ComponentInd(PendingDelete));
}

fn _ValidateAssetType(asset_type: type) void {
    comptime var is_valid = false;

    inline for (AssetComponentsList) |c| {
        if (asset_type == c) {
            is_valid = true;
        }
    }

    if (is_valid == false) {
        @compileError(std.fmt.comptimePrint("Invalid asset type: {s}", @typeName(asset_type)));
    }
}
