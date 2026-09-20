const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @import("AManager.zig");
const EManager = @import("EManager.zig");
const GCManager = @import("GCManager.zig");
const PManager = @import("PManager.zig");
const SManager = @import("SManager.zig");

const EEventData = @import("../Events/EManagerData.zig");
const GCEventData = @import("../Events/GCManagerData.zig");
const PEventData = @import("../Events/PManagerData.zig");
const SEventData = @import("../Events/SManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const ECSManager = @import("../ECS/ECSManager.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const Serializer = @import("../Serializer/Serializer.zig");

const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;

pub fn Core(comptime Self: type) type {
    return struct {
        comptime {
            _ValidateObject(Self);
        }

        pub fn Init(self: *Self, engine_allocator: std.mem.Allocator) !void {
            try self.mECSManager.Init(engine_allocator);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) void {
            self.mECSManager.Deinit(engine_context);
            self.mUUIDToWorldID.deinit(engine_context.EngineAllocator());
            self.mEventManager.Deinit(engine_context.EngineAllocator());
        }

        /// The manager pointer an object of this type carries. An AssetHandle points at
        /// its AManager directly; every other object points at the WorldManager, which is
        /// recoverable because the ECS managers live as fields of it.
        fn ObjManager(self: *Self) @FieldType(UnderlyingObj(Self), "mManager") {
            if (Self == AManager) {
                return self;
            } else if (Self == EManager) {
                return @fieldParentPtr("mEManager", self);
            } else if (Self == GCManager) {
                return @fieldParentPtr("mGCManager", self);
            } else if (Self == PManager) {
                return @fieldParentPtr("mPManager", self);
            } else if (Self == SManager) {
                return @fieldParentPtr("mSManager", self);
            } else {
                @compileError("Not a valid manager type!");
            }
        }

        pub fn CreateObj(self: *Self, engine_context: *EngineContext, config: UnderlyingObj(Self).CreateConfig) !UnderlyingObj(Self) {
            const new_obj: UnderlyingObj(Self) = .{ .mID = try self.mECSManager.CreateEntity(engine_context.EngineAllocator()), .mManager = ObjManager(self) };
            try self.ApplyConfig(engine_context, new_obj.mID, config);
            return new_obj;
        }

        pub fn DeleteObj(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) !void {
            if (Self == SManager) {
                try self.mEventManager.Insert(
                    engine_context.EngineAllocator(),
                    .EndOfFrame,
                    .{ .ToDestroyScene = .{ .Scene = .{ .mID = obj_id, .mManager = ObjManager(self) } } },
                );
            } else {
                //TODO: only SManagerData has a destroy event so far. The other event unions
                //need a ToDestroy<Obj> member and a handler in their OnManagerEvents before
                //this can queue anything, so deletion is a no-op for them right now.
                std.log.err("DeleteObj is not implemented for {s} yet", .{@typeName(Self)});
            }
        }

        pub fn Duplicate(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) !UnderlyingObj(Self) {
            return try self.mECSManager.DuplicateEntity(engine_context, obj_id);
        }

        pub fn CreateChild(self: *Self, engine_context: *EngineContext, parent_id: UnderlyingObjType(Self), child_type: ECSManager.ChildType) !UnderlyingObj(Self) {
            return .{ .mID = try self.mECSManager.AddChild(engine_context.EngineAllocator(), parent_id, child_type), .mManager = ObjManager(self) };
        }

        pub fn AddComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), new_component: anytype) !*@TypeOf(new_component) {
            return try self.mECSManager.AddComponent(engine_context.EngineAllocator(), obj_id, new_component);
        }

        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), comptime component_type: type) !void {
            try self.mECSManager.RemoveComponent(engine_context, obj_id, @TypeOf(self.mECSManager).ComponentInd(component_type));
        }

        pub fn GetComponent(self: *Self, component_type: type, obj_id: UnderlyingObjType(Self)) ?*component_type {
            return self.mECSManager.GetComponent(component_type, obj_id);
        }

        pub fn HasComponent(self: *Self, component_type: type, obj_id: UnderlyingObjType(Self)) bool {
            return self.mECSManager.HasComponent(component_type, obj_id);
        }

        pub fn IsActiveObj(self: *Self, obj_id: UnderlyingObjType(Self)) bool {
            return self.mECSManager.IsActiveEntity(obj_id);
        }

        pub fn SaveObject(_: *Self, engine_context: *EngineContext, object: UnderlyingObj(Self)) !void {
            try engine_context.mSerializer.SaveECSObject(engine_context, object);
        }

        pub fn SaveObjectAs(_: *Self, engine_context: *EngineContext, object: UnderlyingObj(Self)) !void {
            try engine_context.mSerializer.SaveECSObjAs(engine_context, object);
        }

        pub fn LoadObject(self: *Self, engine_context: *EngineContext, abs_path: []const u8) !UnderlyingObj(Self) {
            const new_obj = try CreateObj(self, engine_context, UnderlyingObj(Self).CreateConfig.default);
            engine_context.mSerializer.DeserializeECSObj(engine_context, new_obj, abs_path, .Text);
        }

        pub fn GetGroup(self: *Self, frame_allocator: std.mem.Allocator, comptime query: GroupQuery) !std.ArrayList(UnderlyingObjType(Self)) {
            return try self.mECSManager.GetGroup(frame_allocator, query);
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            self.mECSManager.clearAndFree(engine_context);
            self.mUUIDToWorldID.clearAndFree(engine_context.EngineAllocator());
            self.mEventManager.EventsReset(engine_context.EngineAllocator(), .ClearAndFree);
        }

        pub fn AddUUID(self: *Self, engine_allocator: std.mem.Allocator, uuid: u64, world_id: UnderlyingObjType(Self)) !void {
            try self.mUUIDToWorldID.put(engine_allocator, uuid, world_id);
        }

        pub fn RemoveUUID(self: *Self, uuid: u64) void {
            _ = self.mUUIDToWorldID.remove(uuid);
        }

        pub fn GetWorldID(self: *Self, uuid: u64) ?UnderlyingObjType(Self) {
            return self.mUUIDToWorldID.get(uuid);
        }

        /// Deep copies this manager into `other`, which must be initialized and empty.
        /// Object ids are preserved by the ECS copy, which is what lets the UUID map go across as it
        /// is, and what keeps ids stored in the other managers of the same world pointing at the
        /// right objects once that whole world has been copied.
        /// The manager's own event queue is left alone: its events carry objects that hold a
        /// *WorldManager, which would still be this world's.
        pub fn Copy(self: *Self, engine_context: *EngineContext, other: *Self) !void {
            const engine_allocator = engine_context.EngineAllocator();

            try other.mUUIDToWorldID.ensureTotalCapacity(engine_allocator, self.mUUIDToWorldID.count());
            var iter = self.mUUIDToWorldID.iterator();
            while (iter.next()) |entry| {
                other.mUUIDToWorldID.putAssumeCapacity(entry.key_ptr.*, entry.value_ptr.*);
            }
            errdefer other.mUUIDToWorldID.clearAndFree(engine_allocator);

            try self.mECSManager.Copy(engine_context, &other.mECSManager);
        }

        fn _ValidateObject(manager_t: type) void {
            comptime var is_valid = false;
            if (manager_t == AManager) {
                is_valid = true;
            } else if (manager_t == EManager) {
                is_valid = true;
            } else if (manager_t == GCManager) {
                is_valid = true;
            } else if (manager_t == PManager) {
                is_valid = true;
            } else if (manager_t == SManager) {
                is_valid = true;
            }

            if (!is_valid) {
                @compileError(std.fmt.comptimePrint("Type is not yet a valid ECS Object {s}", .{@typeName(manager_t)}));
            }
        }

        fn UnderlyingObj(manager_t: type) type {
            if (manager_t == AManager) {
                return AssetHandle;
            } else if (manager_t == EManager) {
                return Entity;
            } else if (manager_t == GCManager) {
                return GameContext;
            } else if (manager_t == PManager) {
                return Player;
            } else if (manager_t == SManager) {
                return Scene;
            } else {
                @compileError("Not a valid manager type!");
            }
        }

        fn UnderlyingObjType(manager_t: type) type {
            if (manager_t == AManager) {
                return AssetHandle.Type;
            } else if (manager_t == EManager) {
                return Entity.Type;
            } else if (manager_t == GCManager) {
                return GameContext.Type;
            } else if (manager_t == PManager) {
                return Player.Type;
            } else if (manager_t == SManager) {
                return Scene.Type;
            } else {
                @compileError("Not a valid manager type!");
            }
        }
    };
}
