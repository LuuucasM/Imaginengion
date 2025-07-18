const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const Set = @import("../Vendor/ziglang-set/src/hash_set/managed.zig").HashSetManaged;
const Assets = @import("Assets.zig");
const AssetMetaData = Assets.AssetMetaData;
const FileMetaData = Assets.FileMetaData;
const IDComponent = Assets.IDComponent;
const ScriptAsset = Assets.ScriptAsset;
const AssetsList = Assets.AssetsList;
const AssetHandle = @import("AssetHandle.zig");
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Tracy = @import("../Core/Tracy.zig");

const AssetManager = @This();

const PathType = FileMetaData.PathType;

const ASSET_DELETE_TIMEOUT_NS: i128 = 1_000_000_000;
const MAX_FILE_SIZE: usize = 4_000_000_000;

var AssetM: AssetManager = AssetManager{};
var AssetGPA = std.heap.DebugAllocator(.{}).init;
var AssetMemoryPool = std.heap.ArenaAllocator.init(std.heap.page_allocator);

pub const AssetType = u32;

pub const ECSManagerAssets = ECSManager(AssetType, AssetsList.len);

mAssetECS: ECSManagerAssets = undefined,
mPathToIDEng: std.AutoHashMap(u64, AssetType) = undefined,
mPathToIDPrj: std.AutoHashMap(u64, AssetType) = undefined,
mPathToIDAbs: std.AutoHashMap(u64, AssetType) = undefined,
mCWD: std.fs.Dir = undefined,
mCWDPath: std.ArrayList(u8) = undefined,
mProjectDirectory: ?std.fs.Dir = undefined,
mProjectPath: std.ArrayList(u8) = undefined,

pub fn Init() !void {
    AssetM = AssetManager{
        .mAssetECS = try ECSManagerAssets.Init(AssetGPA.allocator(), &AssetsList),
        .mPathToIDEng = std.AutoHashMap(u64, AssetType).init(AssetGPA.allocator()),
        .mPathToIDPrj = std.AutoHashMap(u64, AssetType).init(AssetGPA.allocator()),
        .mPathToIDAbs = std.AutoHashMap(u64, AssetType).init(AssetGPA.allocator()),
        .mCWD = std.fs.cwd(),
        .mCWDPath = std.ArrayList(u8).init(AssetGPA.allocator()),
        .mProjectPath = std.ArrayList(u8).init(AssetGPA.allocator()),
    };

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    _ = try AssetM.mCWDPath.writer().write(cwd_path);
}

pub fn Deinit() !void {
    AssetM.mAssetECS.Deinit();
    AssetM.mPathToIDEng.deinit();
    AssetM.mPathToIDPrj.deinit();
    AssetM.mPathToIDAbs.deinit();
    AssetM.mCWD.close();
    if (AssetM.mProjectDirectory) |*dir| {
        dir.close();
    }
}

pub fn GetAssetHandleRef(rel_path: []const u8, path_type: PathType) !AssetHandle {
    std.debug.assert(rel_path.len != 0);

    const path_hash = ComputePathHash(rel_path);

    const entity_id = switch (path_type) {
        .Eng => AssetM.mPathToIDEng.get(path_hash),
        .Prj => AssetM.mPathToIDPrj.get(path_hash),
        .Abs => AssetM.mPathToIDAbs.get(path_hash),
    };

    if (entity_id) |id| {
        AssetM.mAssetECS.GetComponent(AssetMetaData, id).mRefs += 1;
        return AssetHandle{
            .mID = id,
        };
    } else {
        const asset_handle = try CreateAsset(rel_path, path_type);
        AssetM.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID).mRefs += 1;
        _ = try switch (path_type) {
            .Eng => AssetM.mPathToIDEng.put(path_hash, asset_handle.mID),
            .Prj => AssetM.mPathToIDAbs.put(path_hash, asset_handle.mID),
            .Abs => AssetM.mPathToIDAbs.put(path_hash, asset_handle.mID),
        };
        return asset_handle;
    }
}

pub fn ReleaseAssetHandleRef(asset_handle: *AssetHandle) void {
    const asset_meta_data = AssetM.mAssetECS.GetComponent(AssetMetaData, asset_handle.mID);
    asset_meta_data.mRefs -= 1;
    asset_handle.mID = AssetHandle.NullHandle;
}

pub fn GetAsset(comptime asset_type: type, asset_id: AssetType) !*asset_type {
    const zone = Tracy.ZoneInit("AssetManager GetAsset", @src());
    defer zone.Deinit();
    //checking the asset type will be evaluated at comptime which will determine which branch
    //the function body will contain so it doesnt get processed in runtime
    //and it is needed because the "meta" asset types dont have an Init(because they are not being)
    //loaded from disk just meta data) so this lets it compile correct
    if (asset_type == FileMetaData or asset_type == AssetMetaData or asset_type == IDComponent) {
        return AssetM.mAssetECS.GetComponent(asset_type, asset_id);
    } else {
        if (AssetM.mAssetECS.HasComponent(asset_type, asset_id)) {
            return AssetM.mAssetECS.GetComponent(asset_type, asset_id);
        } else {
            const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);

            //branch off depending on asset type because script asset doesnt require to open the file, rather it requires the path
            //so that the script can be compiled. both opening a file and getting the abs path requires a system call
            //so ratehr than make 2 system calls for every object and have them all follow the same code we can do a comptime
            //branch and ensure that both assets whos files need to be opened, and ones that are not can both run well
            if (asset_type == ScriptAsset) {
                var buffer: [260 * 2]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const allocator = fba.allocator();

                const abs_path = try GetAbsPath(file_data.mRelPath.items, file_data.mPathType, allocator);

                const new_asset = try ScriptAsset.Init(AssetGPA.allocator(), abs_path);
                return try AssetM.mAssetECS.AddComponent(asset_type, asset_id, new_asset);
            } else {
                const asset_file = try OpenFile(file_data.mRelPath.items, file_data.mPathType);
                defer asset_file.close();

                const new_asset: asset_type = try asset_type.Init(AssetGPA.allocator(), asset_file, file_data.mRelPath.items);
                return try AssetM.mAssetECS.AddComponent(asset_type, asset_id, new_asset);
            }
        }
    }
}

pub fn OnUpdate(frame_allocator: std.mem.Allocator) !void {
    const zone = Tracy.ZoneInit("AssetManager OnUpdate", @src());
    defer zone.Deinit();

    const group = try AssetM.mAssetECS.GetGroup(GroupQuery{ .Component = FileMetaData }, frame_allocator);
    for (group.items) |entity_id| {
        const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, entity_id);
        if (file_data.mSize == 0) {
            try CheckAssetForDeletion(entity_id);
            continue;
        }
        //then check if the asset path is still valid
        if (try GetFileIfExists(file_data.mRelPath.items, file_data.mPathType, entity_id)) |file| {
            defer file.close();

            //check to see if the file needs to be updated
            try CheckLastModified(file, file_data.mLastModified, entity_id);
        }
    }
}

pub fn GetGroup(comptime query: GroupQuery, allocator: std.mem.Allocator) !std.ArrayList(AssetType) {
    return try AssetM.mAssetECS.GetGroup(query, allocator);
}

pub fn OnNewProjectEvent(abs_path: []const u8) !void {
    AssetM.mProjectDirectory = try std.fs.openDirAbsolute(abs_path, .{});

    AssetM.mProjectPath.clearAndFree();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const project_path = try AssetM.mProjectDirectory.?.realpathAlloc(allocator, ".");
    _ = try AssetM.mProjectPath.writer().write(project_path);
}

pub fn OnOpenProjectEvent(abs_path: []const u8) !void {
    AssetM.mProjectDirectory = try std.fs.openDirAbsolute(abs_path, .{});

    AssetM.mProjectPath.clearAndFree();

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const project_path = try AssetM.mProjectDirectory.?.realpathAlloc(allocator, ".");
    _ = try AssetM.mProjectPath.writer().write(project_path);
}

pub fn OpenFile(rel_path: []const u8, path_type: PathType) !std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager OpenFile", @src());
    defer zone.Deinit();
    switch (path_type) {
        .Eng => return try AssetM.mCWD.openFile(rel_path, .{}),
        .Prj => return try AssetM.mProjectDirectory.?.openFile(rel_path, .{}),
        .Abs => return try std.fs.openFileAbsolute(rel_path, .{}),
    }
}

pub fn GetAbsPath(rel_path: []const u8, path_type: PathType, allocator: std.mem.Allocator) ![]const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetAbsPath", @src());
    defer zone.Deinit();

    switch (path_type) {
        .Eng => {
            return try std.fs.path.join(allocator, &[_][]const u8{ AssetM.mCWDPath.items, rel_path });
        },
        .Prj => {
            return try std.fs.path.join(allocator, &[_][]const u8{ AssetM.mProjectPath.items, rel_path });
        },
        .Abs => {
            return rel_path;
        },
    }
}

pub fn GetRelPath(abs_path: []const u8) []const u8 {
    const zone = Tracy.ZoneInit("AssetManager GetRelPath", @src());
    defer zone.Deinit();
    return abs_path[AssetM.mProjectPath.items.len..];
}

pub fn ProcessDestroyedAssets() !void {
    try AssetM.mAssetECS.ProcessDestroyedEntities();
}

fn GetFileIfExists(rel_path: []const u8, path_type: PathType, entity_id: AssetType) !?std.fs.File {
    const zone = Tracy.ZoneInit("AssetManager GetFileIfExists", @src());
    defer zone.Deinit();

    return OpenFile(rel_path, path_type) catch |err| {
        if (err == error.FileNotFound) {
            MarkAssetToDelete(entity_id);
            return null;
        } else {
            return err;
        }
    };
}

fn CheckLastModified(file: std.fs.File, last_modified: i128, entity_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager CheckLastModified", @src());
    defer zone.Deinit();
    const fstats = try file.stat();
    if (last_modified != fstats.mtime) {
        try UpdateAsset(entity_id, file, fstats);
    }
}

fn ComputePathHash(path: []const u8) u64 {
    const zone = Tracy.ZoneInit("AssetManager ComputePathHas", @src());
    defer zone.Deinit();
    var hasher = std.hash.Fnv1a_64.init();
    hasher.update(path);
    return hasher.final();
}

fn CreateAsset(rel_path: []const u8, path_type: PathType) !AssetHandle {
    const zone = Tracy.ZoneInit("AssetManager CreateAsset", @src());
    defer zone.Deinit();

    const new_handle = AssetHandle{
        .mID = try AssetM.mAssetECS.CreateEntity(),
    };
    _ = try AssetM.mAssetECS.AddComponent(AssetMetaData, new_handle.mID, .{
        .mRefs = 0,
    });
    const file_meta_data = try AssetM.mAssetECS.AddComponent(FileMetaData, new_handle.mID, .{
        .mRelPath = std.ArrayList(u8).init(AssetGPA.allocator()),
        .mLastModified = 0,
        .mSize = 0,
        .mHash = 0,
        .mPathType = path_type,
    });

    _ = try file_meta_data.mRelPath.writer().write(rel_path);

    _ = try AssetM.mAssetECS.AddComponent(IDComponent, new_handle.mID, .{
        .ID = try GenUUID(),
    });

    const file = try OpenFile(rel_path, path_type);
    defer file.close();
    const fstats = try file.stat();

    try UpdateAsset(new_handle.mID, file, fstats);

    return new_handle;
}

fn DeleteAsset(asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager DeleteAsset", @src());
    defer zone.Deinit();

    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);

    const path_hash = ComputePathHash(file_data.mRelPath.items);

    _ = switch (file_data.mPathType) {
        .Eng => AssetM.mPathToIDEng.remove(path_hash),
        .Prj => AssetM.mPathToIDPrj.remove(path_hash),
        .Abs => AssetM.mPathToIDAbs.remove(path_hash),
    };

    try AssetM.mAssetECS.DestroyEntity(asset_id);
}

fn MarkAssetToDelete(asset_id: AssetType) void {
    const zone = Tracy.ZoneInit("AssetManager MarkAssetToDelete", @src());
    defer zone.Deinit();

    const file_meta_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    file_meta_data.mLastModified = std.time.nanoTimestamp();
    file_meta_data.mSize = 0;
}

fn UpdateAsset(asset_id: AssetType, file: std.fs.File, fstats: std.fs.File.Stat) !void {
    const zone = Tracy.ZoneInit("AssetManager UpdateAsset", @src());
    defer zone.Deinit();

    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);

    var file_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer file_arena.deinit();
    const allocator = file_arena.allocator();

    var file_hasher = std.hash.Fnv1a_64.init();
    file_hasher.update(try file.readToEndAlloc(allocator, MAX_FILE_SIZE));

    file_data.mHash = file_hasher.final();
    file_data.mLastModified = fstats.mtime;
    file_data.mSize = fstats.size;
}

fn CheckAssetForDeletion(asset_id: AssetType) !void {
    const zone = Tracy.ZoneInit("AssetManager CheckAssetForDelete", @src());
    defer zone.Deinit();

    //check to see if we can recover the asset
    if (try RetryAssetExists(asset_id)) return;

    //if its run out of time then just delete
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);
    if (std.time.nanoTimestamp() - file_data.mLastModified > ASSET_DELETE_TIMEOUT_NS) {
        try DeleteAsset(asset_id);
    }
}

//This function checks again to see if we can open the file maybe there was
//some weird issue last frame but this frame the file is ok so we can recover it
fn RetryAssetExists(asset_id: AssetType) !bool {
    const zone = Tracy.ZoneInit("AssetManager RetryAssetExists", @src());
    defer zone.Deinit();
    const file_data = AssetM.mAssetECS.GetComponent(FileMetaData, asset_id);

    var buffer: [260]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const abs_path = try GetAbsPath(file_data.mRelPath.items, file_data.mPathType, allocator);

    const file = std.fs.openFileAbsolute(abs_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return false;
        } else {
            return err;
        }
    };
    defer file.close();

    const fstats = try file.stat();

    try UpdateAsset(asset_id, file, fstats);

    return true;
}
