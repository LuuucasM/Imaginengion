const std = @import("std");

const ECSManager = @import("../ECS/ECSManager.zig");
const GroupQuery = ECSManager.GroupQuery;

const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
pub const EventData = @import("../Events/AManagerData.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const AssetComponents = @import("../ECSComponents/AComponents.zig");
const AssetComponentsList = AssetComponents.ComponentsList;
const FileMetaData = AssetComponents.FileMetaData;
const AssetMetaData = AssetComponents.AssetMetaData;
const GenMetaData = AssetComponents.GenMetaData;
const Texture2D = AssetComponents.Texture2D;
const TextAsset = AssetComponents.TextAsset;
const AudioAsset = AssetComponents.AudioAsset;
const EngineContext = @import("../Core/EngineContext.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const AManager = @This();

const ASSET_DELETE_TIMEOUT_NS: i96 = 1_000_000_000;

pub const ECSManagerT = ECSManager.ECSManager(AssetHandle.Type, &AssetComponentsList, "AssetECS");
pub const EventManagerT = EventManager.EventManager(EventData);

const Tracy = @import("../Core/Tracy.zig");

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

pub const PendingDelete = struct {
    Reason: u32,
    Time: std.Io.Timestamp,
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
    };
    pub fn Deinit(self: *InternalData, engine_context: *EngineContext) void {
        self.DefaultFileMetaData.Deinit(engine_context);
        self.DefaultTexture2D.Deinit(engine_context);
        self.DefaultTextAsset.Deinit(engine_context);
        self.DefaultAudioAsset.Deinit(engine_context);
    }
    DefaultFileMetaData: FileMetaData,
    DefaultTexture2D: Texture2D,
    DefaultTextAsset: TextAsset,
    DefaultAudioAsset: AudioAsset,
};

pub const empty: AManager = .{
    .mECSManager = .empty,
    .mEventManager = .empty,
    .mUUIDToWorldID = .empty,
    .mCWD = undefined,
    .mCWDPath = .empty,
    .mProjectDirectory = null,
    .mProjectPath = .empty,
    .mPendingDelete = .empty,
    ._internal = .uninit,
};

const Core = ECSCore(AManager);

mECSManager: ECSManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, AssetHandle.Type),

mEventManager: EventManagerT,

mCWD: std.Io.Dir,
mCWDPath: std.ArrayList(u8),
mProjectDirectory: ?std.Io.Dir,
mProjectPath: std.ArrayList(u8),
mPendingDelete: std.AutoArrayHashMapUnmanaged(AssetHandle.Type, PendingDelete),
_internal: InternalData,

pub fn Init(self: *AManager, engine_context: *EngineContext) !void {
    try self.mECSManager.Init(engine_context.EngineAllocator());

    self.mCWD = std.Io.Dir.cwd();
    const cwd_path = try self.mCWD.realPathFileAlloc(engine_context.Io(), ".", engine_context.FrameAllocator());
    _ = try self.mCWDPath.print(engine_context.EngineAllocator(), "{s}", .{cwd_path});
}

///Setup needed to initialize "default" assets
pub fn Setup(self: *AManager, engine_context: *EngineContext) !void {
    const frame_allocator = engine_context.FrameAllocator();
    const io = engine_context.Io();

    //FILE META DATA =======================
    _ = try self._internal.DefaultFileMetaData.mRelPath.appendSlice(engine_context.EngineAllocator(), "default");

    //TEXTURE 2D =========================
    const texture2d_rel_path = "src/Imaginengion/EngineAssets/textures/DefaultTexture.png";
    const texture2d_abs_path = try self.GetAbsPath(frame_allocator, texture2d_rel_path, .Eng);
    const texture2d_file = try std.Io.Dir.openFileAbsolute(io, texture2d_abs_path, .{});
    defer texture2d_file.close(io);
    try self._internal.DefaultTexture2D.Init(engine_context, texture2d_abs_path, texture2d_rel_path, texture2d_file);

    //TEXT ================================
    const text_rel_path = "src/Imaginengion/EngineAssets/fonts/default/static/ChironGoRoundTC-Regular.ttf";
    const text_abs_path = try self.GetAbsPath(frame_allocator, text_rel_path, .Eng);
    const text_file = try std.Io.Dir.openFileAbsolute(io, text_abs_path, .{});
    defer text_file.close(io);
    try self._internal.DefaultTextAsset.Init(engine_context, text_abs_path, text_rel_path, text_file);

    //AUDIO =================================
    const audio_rel_path = "src/Imaginengion/EngineAssets/sounds/DefaultSound.mp3";
    const audio_abs_path = try self.GetAbsPath(frame_allocator, audio_rel_path, .Eng);
    const audio_file = try std.Io.Dir.openFileAbsolute(io, audio_abs_path, .{});
    defer audio_file.close(io);
    try self._internal.DefaultAudioAsset.Init(engine_context, audio_abs_path, audio_rel_path, audio_file);
}

pub fn Deinit(self: *AManager, engine_context: *EngineContext) void {
    Core.Deinit(self, engine_context);
    self.mCWDPath.deinit(engine_context.EngineAllocator());
    self.mProjectPath.deinit(engine_context.EngineAllocator());

    self.mCWD.close(engine_context.Io());
    if (self.mProjectDirectory) |p_dir| p_dir.close(engine_context.Io());
    self.mPendingDelete.deinit(engine_context.EngineAllocator());

    self._internal.Deinit(engine_context);
}

pub fn GetAssetHandle(self: *AManager, engine_context: *EngineContext, asset_source: AssetSource) !AssetHandle {
    if (asset_source == .Default) {
        return AssetHandle{
            .mID = AssetHandle.NullObject,
            .mManager = self,
        };
    }

    const asset_hash = switch (asset_source) {
        .File => |f| blk: {
            const abs_path = try self.GetAbsPath(engine_context.FrameAllocator(), f.rel_path, f.path_type);
            break :blk ComputePathHash(abs_path);
        },
        .Computed => |c| c.GetUUID(),
        .Default => unreachable,
    };

    const asset_id = self.GetWorldID(asset_hash);

    const engine_allocator = engine_context.EngineAllocator();

    if (asset_id) |id| {
        std.debug.assert(self.mECSManager.HasComponent(AssetMetaData, id));
        self.mECSManager.GetComponent(AssetMetaData, id).?.mRefs += 1;
        return AssetHandle{ .mID = id, .mManager = self };
    } else {
        const new_asset_id = switch (asset_source) {
            .File => |f| try self.CreateAssetFile(engine_context, f),
            .Computed => try self.CreateAssetGen(engine_allocator),
            .Default => unreachable,
        };

        self.mECSManager.GetComponent(AssetMetaData, new_asset_id).?.mRefs += 1;

        try self.AddUUID(engine_allocator, asset_hash, new_asset_id);

        return AssetHandle{ .mID = new_asset_id, .mManager = self };
    }
}

/// Takes another reference to an asset that is already loaded, for code that copies a handle it owns.
pub fn RetainAssetHandle(self: *AManager, asset_id: AssetHandle.Type) void {
    self.mECSManager.GetComponent(AssetMetaData, asset_id).?.mRefs += 1;
}

pub fn ReleaseAssetHandle(self: *AManager, asset_handle: *AssetHandle) void {
    const asset_meta_data = self.mECSManager.GetComponent(AssetMetaData, asset_handle.mID).?;
    asset_meta_data.mRefs -= 1;
    asset_handle.mID = AssetHandle.NullObject;
}

pub fn GetAsset(self: *AManager, engine_context: *EngineContext, comptime asset_type: type, asset_id: AssetHandle.Type) !*asset_type {
    _ValidateAssetType(asset_type);

    if (self.mECSManager.IsActiveEntity(asset_id)) {
        if (self.mECSManager.GetComponent(asset_type, asset_id)) |asset| {
            return asset;
        } else {
            //only the load is zoned: the hit path above is a lookup that runs for every drawn shape
            const zone = Tracy.ZoneInit("AssetManager::LoadAsset", @src());
            defer zone.Deinit();

            const file_data = self.mECSManager.GetComponent(FileMetaData, asset_id).?;
            zone.Text(file_data.mRelPath.items);
            //TODO: maybe a check to ensure rel path is valid?

            const abs_path = try self.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);

            const asset_file = try self.OpenFile(engine_context, file_data.mRelPath.items, file_data.mPathType);
            defer self.CloseFile(engine_context.Io(), asset_file);

            var asset_component = asset_type{};
            asset_component.Init(engine_context, abs_path, file_data.mRelPath.items, asset_file) catch |err| {
                if (err == error.AssetInitFailed) {
                    std.log.err("Failed To initialize asset {s} for asset type {s}\n", .{ abs_path, @typeName(asset_type) });
                    return try self.GetDefaultAsset(asset_type);
                } else return err;
            };

            return self.mECSManager.AddComponent(engine_context.EngineAllocator(), asset_id, asset_component);
        }
    } else {
        return try self.GetDefaultAsset(asset_type);
    }
}

pub fn GetFileMetaData(self: *AManager, id: AssetHandle.Type) *FileMetaData {
    if (self.mECSManager.IsActiveEntity(id)) {
        return self.mECSManager.GetComponent(FileMetaData, id).?;
    } else {
        return &self._internal.DefaultFileMetaData;
    }
}

pub fn OnUpdate(self: *AManager, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AssetManager::OnUpdate", @src());
    defer zone.Deinit();

    const frame_allocator = engine_context.FrameAllocator();

    //check through all the assets we currently have to see if they are still valid/need to be updated
    const group = try self.mECSManager.GetGroup(frame_allocator, .{ .Component = FileMetaData });
    zone.Value(group.items.len);
    Tracy.Plot("Assets/Tracked Files", .{ .color = 0x607D8B }, group.items.len);
    Tracy.Plot("Assets/Pending Delete", .{ .color = 0x9E9E9E }, self.mPendingDelete.count());
    for (group.items) |asset_id| {
        const file_data = self.mECSManager.GetComponent(FileMetaData, asset_id).?;

        //stat first: it costs no handle, and it is what tells us the file still exists
        const stat = self.OpenFileStats(engine_context, file_data.mRelPath.items, file_data.mPathType) catch |err| {
            if (err == error.FileNotFound) {
                try self.MarkForDelete(engine_context, asset_id, .FileNotFound);
                continue;
            }
            return err;
        };

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
            try self.mEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .FileUpdate = .{ .mAssetID = asset_id } });
        }
    }

    var iter = self.mPendingDelete.iterator();
    const t1 = std.Io.Timestamp.now(engine_context.Io(), .awake);
    while (iter.next()) |entry| {
        const asset_id = entry.key_ptr.*;
        const pending_delete = entry.value_ptr.*;

        //TODO: here I can add different things to see if I can possibly recover the file based on its different reasons

        const duration = pending_delete.Time.durationTo(t1);
        const ns = duration.toNanoseconds();
        if (ns > ASSET_DELETE_TIMEOUT_NS) {
            try self.mEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .ToDestroyAsset = .{ .mAssetID = asset_id } });
        }
    }
}

pub fn OnNewProjectEvent(self: *AManager, engine_context: *EngineContext, abs_path: []const u8) !void {
    if (self.mProjectDirectory) |*dir| {
        dir.close(engine_context.Io());
        self.mProjectDirectory = null;
    }

    self.mProjectPath.clearAndFree(engine_context.EngineAllocator());

    self.mProjectDirectory = try std.Io.Dir.openDirAbsolute(engine_context.Io(), abs_path, .{});

    _ = try self.mProjectPath.print(engine_context.EngineAllocator(), "{s}", .{abs_path});
}

pub fn OnOpenProjectEvent(self: *AManager, engine_context: *EngineContext, abs_path: []const u8) !void {
    if (self.mProjectDirectory) |*dir| {
        dir.close(engine_context.Io());
        self.mProjectDirectory = null;
    }

    self.mProjectPath.clearAndFree(engine_context.EngineAllocator());

    const dir_name = std.fs.path.dirname(abs_path).?;

    self.mProjectDirectory = try std.Io.Dir.openDirAbsolute(engine_context.Io(), dir_name, .{});

    _ = try self.mProjectPath.print(engine_context.EngineAllocator(), "{s}", .{dir_name});
}

pub fn OpenFileStats(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File.Stat {
    const zone = Tracy.ZoneInit("AssetManager::OpenFileStats", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => return try self.mCWD.statFile(engine_context.Io(), rel_path, .{}),
        .Prj => return try self.mProjectDirectory.?.statFile(engine_context.Io(), rel_path, .{}),
        .Gen => return error.NoFileToOpen,
    }
}

pub fn OpenFile(self: *AManager, engine_context: *EngineContext, rel_path: []const u8, path_type: PathType) !std.Io.File {
    const zone = Tracy.ZoneInit("AssetManager::OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try self.mCWD.openFile(engine_context.Io(), rel_path, .{}),
        .Prj => return try self.mProjectDirectory.?.openFile(engine_context.Io(), rel_path, .{}),
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
            return try std.fs.path.join(allocator, &[_][]const u8{ self.mProjectPath.items, rel_path });
        },
        .Gen => unreachable,
    }
}

pub fn GetRelPath(self: *AManager, abs_path: []const u8, path_type: PathType) []const u8 {
    return switch (path_type) {
        .Eng => abs_path[self.mCWDPath.items.len + 1 ..],
        .Prj => abs_path[self.mProjectPath.items.len + 1 ..],
        .Gen => unreachable,
    };
}

//From general managers
pub const GetGroup = Core.GetGroup;

pub const SetSyncCallback = Core.SetSyncCallback;

pub const IsActiveObj = Core.IsActiveObj;

pub fn clearAndFree(self: *AManager, engine_context: *EngineContext) void {
    Core.clearAndFree(self, engine_context);
    self.mPendingDelete.clearAndFree(engine_context.EngineAllocator());
    if (self.mProjectDirectory) |dir| {
        dir.close(engine_context.Io());
        self.mProjectDirectory = null;
    }
    self.mProjectPath.clearAndFree(engine_context.EngineAllocator());
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
        self.mEventManager.ClearCategory(engine_context.EngineAllocator(), event_category, .ClearRetainingCapacity);
    } else {
        std.log.err("AManager.ProcessEvents does not currently handle processing events of type {s}", .{@typeName(event_data)});
    }
}

/// Runs the asset destroys queued this frame: the manager events hand each dead asset to the ECS
/// as a destroy, then the ECS events actually free it.
pub fn ProcessDestroyedAssets(self: *AManager, engine_context: *EngineContext) !void {
    var callback_list: std.DoublyLinkedList = .{};
    try self.ProcessEvents(EventData, .EndOfFrame, engine_context, &callback_list);
    try self.mECSManager.ProcessEvents(engine_context, .EndOfFrame, &callback_list);
}

pub fn OnManagerEvents(self: *AManager, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventManager.EventResult {
    switch (event) {
        .FileUpdate => |e| {
            inline for (AssetComponents.FileUpdateList) |comp_type| {
                if (self.mECSManager.HasComponent(comp_type, e.mAssetID)) {
                    try self.mECSManager.RemoveComponent(engine_context, e.mAssetID, ECSManagerT.ComponentInd(comp_type));
                }
            }
        },
        .ToDestroyAsset => |e| {
            const file_data = self.mECSManager.GetComponent(FileMetaData, e.mAssetID).?;
            const abs_path = try self.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);
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

    const engine_allocator = engine_context.EngineAllocator();

    const new_asset_id = try self.mECSManager.CreateEntity(engine_allocator);

    _ = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, AssetMetaData{ .mRefs = 0 });

    var file_meta_data = FileMetaData{
        .mPathType = file_source.path_type,
    };
    _ = try file_meta_data.mRelPath.print(engine_allocator, "{s}", .{file_source.rel_path});
    const new_file_data = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, file_meta_data);

    const file = try self.OpenFile(engine_context, file_source.rel_path, file_source.path_type);
    defer self.CloseFile(engine_context.Io(), file);
    const fstats = try file.stat(engine_context.Io());

    try new_file_data.UpdateMetaData(engine_context, file, fstats);

    return new_asset_id;
}

fn CreateAssetGen(self: *AManager, engine_allocator: std.mem.Allocator) !AssetHandle.Type {
    const zone = Tracy.ZoneInit("AssetManager::CreateAssetGen", @src());
    defer zone.Deinit();

    const new_asset_id = try self.mECSManager.CreateEntity(engine_allocator);

    _ = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, AssetMetaData{ .mRefs = 0 });
    _ = try self.mECSManager.AddComponent(engine_allocator, new_asset_id, GenMetaData{});

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
    } else {
        //not every asset type has a stand-in; those just fail the load instead
        std.log.err("No default asset available for asset type {s}", .{@typeName(asset_type)});
        return error.NoDefaultAsset;
    }
}

fn MarkForDelete(self: *AManager, engine_context: *EngineContext, asset_id: AssetHandle.Type, reason: AssetErrorFlags.Reason) !void {
    if (self.mPendingDelete.getPtr(asset_id)) |pending_data| {
        switch (reason) {
            .FileNotFound => pending_data.Reason |= AssetErrorFlags.FileNotFound,
        }
    } else {
        const error_flags = switch (reason) {
            .FileNotFound => AssetErrorFlags.FileNotFound,
        };
        try self.mPendingDelete.put(
            engine_context.EngineAllocator(),
            asset_id,
            .{ .Reason = error_flags, .Time = std.Io.Timestamp.now(engine_context.Io(), .awake) },
        );
    }
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
