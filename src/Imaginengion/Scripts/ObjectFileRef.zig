//! A script variable that names an object's file and holds the object loaded from it: a file dropped on it in the editor
//! is what a built game can load, where an object variable can only point at something already loaded. It is the one
//! variable a script needs for "this menu": Get hands back the one it has, or loads the file the first time.
//! mFile holds a reference on the file's asset, so the engine keeps the count (ScriptValues.RetainRefs, ReleaseRefs).
//! A script reads a ref and calls Get and Spawn but never assigns one: a copy of the handle would be released twice
const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const RefMap = @import("../ECSObjects/ECSObject.zig").RefMap;
const Serializer = @import("../Serializer/Serializer.zig");
const Inspector = @import("../UI/Inspector.zig");
const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");
const PathType = @import("../ECSManagers/AManager.zig").PathType;

/// For a copy of an object put in `world` (a template's copy, a duplicate): an entity handle pointing into what was
/// copied points at its copy instead, one pointing elsewhere in `world` stays, and one pointing into another world (a
/// template's own) is cleared
pub fn RemapObject(object: anytype, ref_map: *const RefMap, world: *WorldManager) void {
    const obj_t = @TypeOf(object.*);
    if (object.mID == obj_t.NullObject) return;
    if (obj_t == Entity) {
        if (ref_map.Get(object.*)) |copy| {
            object.* = copy;
            return;
        }
    }
    if (object.mManager != world) object.* = .uninit;
}

pub fn ObjectFileRef(comptime obj_t: type) type {
    return struct {
        const Self = @This();

        /// The type of object it loads
        pub const Object = obj_t;
        /// What an object of this type goes in: the world, or for an entity the scene
        pub const Where = if (obj_t == Entity) Scene else *WorldManager;
        const EXTENSIONS: []const []const u8 = &.{std.mem.span(Serializer.FileExtension(obj_t))};

        pub const uninit: Self = .{};

        mFile: AssetHandle = .uninit,
        mObject: obj_t = .uninit,

        /// The object it holds if that is still there, otherwise a new one read from the file, UUID and all, which it
        /// then holds. For one specific thing, like a menu: see Spawn for many of them. error.NoFileSet if it has neither
        pub fn Get(self: *Self, engine_context: *EngineContext, where: Where) !obj_t {
            if (self.mObject.IsActive()) return self.mObject;
            if (!self.mFile.IsIDValid()) return error.NoFileSet;
            const file_data = self.mFile.GetFileMetaData();
            self.mObject = if (obj_t == Entity)
                try where.LoadEntity(engine_context, file_data.mRelPath.items, file_data.mPathType)
            else
                try where.Load(obj_t, engine_context, file_data.mRelPath.items, file_data.mPathType);
            return self.mObject;
        }

        /// A new copy of the file as a template each call, with no UUID, without changing the object it holds.
        /// error.NoFileSet if it has no file
        pub fn Spawn(self: *const Self, engine_context: *EngineContext, where: Where) !obj_t {
            if (!self.mFile.IsIDValid()) return error.NoFileSet;
            if (obj_t == Entity) return try where.Spawn(engine_context, self.mFile);
            return try where.Spawn(obj_t, engine_context, self.mFile);
        }

        /// Takes a reference on the file for a copy of this ref
        pub fn Retain(self: Self) void {
            self.mFile.RetainAsset();
        }

        /// Gives back this ref's reference on the file
        pub fn Release(self: *Self) void {
            self.mFile.ReleaseAsset();
        }

        /// Whether it has anything worth saving
        pub fn IsSet(self: Self) bool {
            return self.mFile.IsIDValid() or self.mObject.IsActive();
        }

        /// Points the object at `world`: for a copy of a whole world, where ids carry over. The file's asset manager is
        /// the one every world shares
        pub fn Retarget(self: *Self, world: *WorldManager) void {
            self.mObject.mManager = world;
        }

        /// For a copy of this ref's owner, see RemapObject. The file stays, so Get can load one for the copy
        pub fn RemapRefs(self: *Self, ref_map: *const RefMap, world: *WorldManager) void {
            RemapObject(&self.mObject, ref_map, world);
        }

        pub fn UIRender(self: *Self, ui: *Inspector.Builder) !void {
            try ui.Asset(&self.mFile, "File", EXTENSIONS, .{});
            _ = switch (obj_t) {
                Entity => try ui.EntityRef(&self.mObject, "Loaded", .{}),
                Scene => try ui.SceneRef(&self.mObject, "Loaded", .{}),
                Player => try ui.PlayerRef(&self.mObject, "Loaded", .{}),
                GameContext => try ui.GameContextRef(&self.mObject, "Loaded", .{}),
                else => @compileError(@typeName(obj_t) ++ " is not an object type"),
            };
        }

        /// The file as every asset reference is written, and the object as its UUID. Each left out when it isn't set
        pub fn jsonStringify(self: *const Self, jw: anytype) !void {
            try jw.beginObject();
            if (self.mFile.IsIDValid()) {
                try jw.objectField("File");
                try jw.write(self.mFile);
            }
            if (self.mObject.IsActive()) {
                if (self.mObject.GetComponent(UUIDComponent)) |uuid| {
                    try jw.objectField("Object");
                    try jw.write(uuid.ID);
                }
            }
            try jw.endObject();
        }

        /// Takes the file from `value`, a JSON object jsonStringify made. One that can't be found, or isn't this type's
        /// kind of file (the script was changed since), leaves it as it is. The object is up to the caller, which knows
        /// which variable this is to ask for it (ScriptValues.Read)
        pub fn ReadFile(self: *Self, engine_context: *EngineContext, value: std.json.Value) !void {
            const file = value.object.get("File") orelse return;
            if (file != .object) return;
            const path = file.object.get("Path") orelse return;
            const path_type_name = file.object.get("PathType") orelse return;
            if (path != .string or path_type_name != .string) return;
            const path_type = std.meta.stringToEnum(PathType, path_type_name.string) orelse return;
            if (!std.ascii.eqlIgnoreCase(std.fs.path.extension(path.string), EXTENSIONS[0])) {
                std.log.warn("{s} can't go in a variable that takes {s} files", .{ path.string, EXTENSIONS[0] });
                return;
            }

            const handle = engine_context.mAssetManager.GetAssetHandle(engine_context, .{ .File = .{ .rel_path = path.string, .path_type = path_type } }) catch |err| {
                std.log.warn("couldn't find {s}, a file a script variable points at: {s}", .{ path.string, @errorName(err) });
                return;
            };
            self.mFile.ReleaseAsset();
            self.mFile = handle;
        }
    };
}
