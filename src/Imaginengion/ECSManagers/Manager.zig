const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @import("AManager.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
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
const Voice = @import("../ECSObjects/Voice.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const UUIDComponent = @import("../ECSComponents/Shared/UUIDComponent.zig");

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

        /// Points both of this manager's event managers (its own and its ECS manager's) at the
        /// engine-wide synchronous listener. Called once at startup via WorldManager/EngineContext.
        pub fn SetSyncCallback(self: *Self, ctx: anytype, comptime handler: anytype) void {
            self.mEventManager.SetSyncCallback(ctx, handler);
            self.mECSManager.SetSyncCallback(ctx, handler);
        }

        /// The manager pointer an object of this type carries. The engine level managers' objects (AssetHandle,
        /// Voice) point at their manager directly; every other object points at the WorldManager, which is
        /// recoverable because the ECS managers live as fields of it.
        fn ObjManager(self: *Self) @FieldType(UnderlyingObj(Self), "mManager") {
            if (Self == AManager or Self == AudioManager) {
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

        /// Queues the object's delete for the end of the frame, when the manager's ProcessEvents hands it to
        /// Self.OnManagerEvents, so it stays usable until then.
        /// Deleting an object that is already gone, or that is already queued this frame, does nothing.
        pub fn DeleteObj(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) !void {
            if (!self.mECSManager.IsActiveEntity(obj_id)) return;

            const obj: UnderlyingObj(Self) = .{ .mID = obj_id, .mManager = ObjManager(self) };
            const event: Self.EventManagerT.EventType = if (Self == EManager)
                .{ .DestroyEntity = .{ .Entity = obj } }
            else if (Self == GCManager)
                .{ .DestroyGameContext = .{ .GameContext = obj } }
            else if (Self == PManager)
                .{ .DestroyPlayer = .{ .Player = obj } }
            else if (Self == SManager)
                .{ .ToDestroyScene = .{ .Scene = obj } }
            else if (Self == AudioManager)
                .{ .DestroyVoice = .{ .Voice = obj } }
            else
                @compileError(std.fmt.comptimePrint("DeleteObj is not implemented for {s} yet", .{@typeName(Self)}));

            for (self.mEventManager.mEventsArray.getPtr(.EndOfFrame).items) |queued_event| {
                if (std.meta.eql(queued_event, event)) return;
            }
            try self.mEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, event);
        }

        /// ECS event listener each manager's ProcessEvents adds when it hands its ECS the ECSEventData category:
        /// takes a destroyed object's UUID out of the manager's map. That covers children and scripts too,
        /// which the ECS queues itself when their parent goes. Runs before the ECS's own handler, so the
        /// object is still readable here.
        pub fn RemoveDestroyedUUID(ctx: *anyopaque, _: *EngineContext, event: *const Self.ECSManagerT.ECSEventDataT.EventT) anyerror!EventResult {
            const self: *Self = @ptrCast(@alignCast(ctx));
            switch (event.*) {
                .DestroyEntity => |e| {
                    //the same destroy can be queued twice in one pass, and the second one finds it gone
                    if (!self.mECSManager.IsActiveEntity(e.mEntityID)) return .Continue;
                    const uuid_component = self.mECSManager.GetComponent(UUIDComponent, e.mEntityID) orelse return .Continue;
                    //a duplicate carries its original's UUID without owning the map entry
                    if (self.GetWorldID(uuid_component.ID) == e.mEntityID) self.RemoveUUID(uuid_component.ID);
                },
                else => {},
            }
            return .Continue;
        }

        pub fn Duplicate(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) !UnderlyingObj(Self) {
            return .{ .mID = try self.mECSManager.DuplicateEntity(engine_context, obj_id), .mManager = ObjManager(self) };
        }

        pub fn CreateChild(self: *Self, engine_context: *EngineContext, parent_id: UnderlyingObjType(Self), child_type: ECSManager.ChildType, config: UnderlyingObj(Self).CreateConfig) !UnderlyingObj(Self) {
            const new_child: UnderlyingObj(Self) = .{ .mID = try self.mECSManager.AddChild(engine_context.EngineAllocator(), parent_id, child_type), .mManager = ObjManager(self) };
            try self.ApplyConfig(engine_context, new_child.mID, config);
            return new_child;
        }

        pub fn AddComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), new_component: anytype) !*@TypeOf(new_component) {
            const component_ptr = try self.mECSManager.AddComponent(engine_context.EngineAllocator(), obj_id, new_component);

            //a transform that has just been added has never been through a transform pass, so its
            //world values are still the InternalData defaults. Those defaults only happen to be
            //right for a root sitting at the origin: a child needs the pass to pick up its parent's
            //world transform, or it renders at the origin at its own local size. This is the one
            //place every route goes through (ApplyConfig, Entity's own AddComponent, the components
            //panel, deserialization), so none of them has to remember to tag. The tag lands in a
            //different sparse set, so component_ptr stays valid.
            if (comptime Self == EManager and @TypeOf(new_component) == EntityTransformComponent) {
                if (!self.mECSManager.HasComponent(TransformDirtyTag, obj_id)) {
                    _ = try self.mECSManager.AddComponent(engine_context.EngineAllocator(), obj_id, TransformDirtyTag{});
                }
            }

            //a new rigid body starts with whatever _InvMass it was constructed with (zero for a
            //default one, so static), and BroadPass reads the tag rather than the mass
            if (comptime Self == EManager and @TypeOf(new_component) == RigidBodyComponent) {
                const entity: Entity = .{ .mID = obj_id, .mManager = ObjManager(self) };
                try entity.SyncBodyTags(engine_context);
            }

            return component_ptr;
        }

        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), comptime component_type: type) !void {
            //the body tags describe a rigid body that is on its way out, so they come off now.
            //SyncBodyTags would re-add one instead: this removal is only queued, so the component
            //is still readable until the end of the frame.
            if (comptime Self == EManager and component_type == RigidBodyComponent) {
                const entity: Entity = .{ .mID = obj_id, .mManager = ObjManager(self) };
                try entity.ClearBodyTags(engine_context);
            }

            try self.mECSManager.RemoveComponent(engine_context, obj_id, @TypeOf(self.mECSManager).ComponentInd(component_type));
        }

        /// Immediate counterpart to RemoveComponent; see ECSManager.RemoveComponentSync for when
        /// it is safe to use.
        pub fn RemoveComponentSync(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), comptime component_type: type) !void {
            try self.mECSManager.RemoveComponentSync(engine_context, obj_id, @TypeOf(self.mECSManager).ComponentInd(component_type));
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

        /// Blank, every component comes from the file
        pub fn LoadObject(self: *Self, engine_context: *EngineContext, abs_path: []const u8) !UnderlyingObj(Self) {
            if (Self == EManager) @compileError("an entity has to belong to a scene, load it with Scene.LoadEntity");
            const new_obj = try CreateObj(self, engine_context, UnderlyingObj(Self).BlankConfig);
            try engine_context.mSerializer.DeserializeECSObj(engine_context, new_obj, abs_path, .Text);
            return new_obj;
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
            } else if (manager_t == AudioManager) {
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
            } else if (manager_t == AudioManager) {
                return Voice;
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
            } else if (manager_t == AudioManager) {
                return Voice.Type;
            } else {
                @compileError("Not a valid manager type!");
            }
        }
    };
}
