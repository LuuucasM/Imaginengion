const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Tracy = @import("../../Core/Tracy.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const Scene = @import("../../ECSObjects/Scene.zig");
const Player = @import("../../ECSObjects/Player.zig");
const GameContext = @import("../../ECSObjects/GameContext.zig");
const TextSerializer = @import("../../Serializer/TextSerializer.zig");

/// An ECS object's file (entity, scene, player or game context) loaded once into EngineContext.mAssetWorld,
/// so the file is parsed once and copied from after that. `name` is the asset component's Name.
pub fn ObjectAsset(comptime obj_t: type, comptime name: []const u8) type {
    return struct {
        const Self = @This();

        pub const Name: []const u8 = name;

        pub const empty: Self = .{
            .mObject = .uninit,
        };

        /// The loaded object (the root of its tree), which lives in EngineContext.mAssetWorld
        mObject: obj_t = .uninit,

        pub fn Init(self: *Self, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.Io.File) !void {
            const zone = Tracy.ZoneInit(name ++ "::Init", @src());
            defer zone.Deinit();
            zone.Text(rel_path);

            const object = try CreateBlank(engine_context);
            errdefer Destroy(engine_context, object);

            //TextSerializer rather than Serializer.DeserializeECSObj: that one also records the object as the
            //file's owner in mFileObjects, which would take an asset handle to the very asset being loaded
            try TextSerializer.DeserializeECSObj(engine_context, object, abs_path);
            engine_context.mSerializer.ResolveUUIDs();

            self.mObject = object;
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            //at shutdown the asset world is emptied before the asset manager (see EngineContext.DeInit),
            //so the object is already gone by the time this runs
            if (!self.mObject.IsActive()) return;
            Destroy(engine_context, self.mObject);
            self.mObject = .uninit;
        }

        /// Loaded assets are shared through handles rather than copied, and a plain copy would point at the
        /// same object and delete it twice
        pub fn Clone(_: *const Self, _: *EngineContext) !Self {
            return error.AssetNotDuplicatable;
        }

        /// Blank, every component comes from the file
        fn CreateBlank(engine_context: *EngineContext) !obj_t {
            const asset_world = &engine_context.mAssetWorld;
            if (obj_t == Entity) {
                //an entity has to belong to a scene
                return try engine_context.mAssetEntityScene.CreateEntity(engine_context, Entity.BlankConfig);
            } else if (obj_t == Scene) {
                //left out of the stack until the file's SceneComponent slots it in
                return try asset_world.mSManager.CreateBlankScene(engine_context);
            } else if (obj_t == Player) {
                return try asset_world.CreatePlayer(engine_context, Player.BlankConfig);
            } else if (obj_t == GameContext) {
                return try asset_world.CreateGameContext(engine_context, GameContext.BlankConfig);
            } else {
                @compileError(std.fmt.comptimePrint("{s} can not be loaded as an asset", .{@typeName(obj_t)}));
            }
        }

        /// Takes the whole tree along (a scene's entities too), and its UUIDs out of the asset world, when the
        /// asset world's events are processed
        fn Destroy(engine_context: *EngineContext, object: obj_t) void {
            object.Delete(engine_context) catch |err| {
                std.log.err(name ++ " failed to delete its object: {s}", .{@errorName(err)});
            };
        }
    };
}
