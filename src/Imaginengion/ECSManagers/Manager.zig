const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");

const AManager = @import("AManager.zig");
const AudioManager = @import("../AudioManager/AudioManager.zig");
const UIManager = @import("../UI/UIManager.zig");
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
const UIElement = @import("../ECSObjects/UIElement.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityTransformComponent = EntityComponents.TransformComponent;
const TransformDirtyTag = EntityComponents.TransformDirtyTag;
const RigidBodyComponent = EntityComponents.RigidBodyComponent;
const LayoutComponent = EntityComponents.LayoutComponent;
const LayoutItemComponent = EntityComponents.LayoutItemComponent;
const TextComponent = EntityComponents.TextComponent;
const UIElementComponent = EntityComponents.UIElementComponent;
const StyleSystem = @import("../UI/StyleSystem.zig");
const LayoutSystem = @import("../UI/LayoutSystem.zig");
const ShapeComponent = EntityComponents.ShapeComponent;
const SurfaceComponent = EntityComponents.SurfaceComponent;
const DisabledTag = EntityComponents.DisabledTag;
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
            HookRemovals(self);
        }

        /// Has the ECS tell OnComponentRemoved and OnObjectDestroyed about every removal and destroy. Part of Init, for
        /// a manager with an Init of its own to call
        pub fn HookRemovals(self: *Self) void {
            self.mECSManager.SetRemovalHook(.{ .mCtx = self, .mFn = OnECSRemoval });
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
        const _InWorld = Self == EManager or Self == GCManager or Self == PManager or Self == SManager;

        /// Structural operations (creating, deleting) and the bookkeeping adding and removing set off run unchecked (see
        /// ECSManager.UncheckedRecord) on every ECS they can reach: for the world's objects all four of the world's,
        /// since they reach across them (deleting a scene reads its entities), otherwise the manager's own
        const Unchecked = struct {
            mWorld: if (_InWorld) WorldManager.UncheckedScope else void = if (_InWorld) .{} else {},
            mOwn: if (_InWorld) void else Self.ECSManagerT.SystemRecord = if (_InWorld) {} else Self.ECSManagerT.UncheckedRecord,

            fn Enter(unchecked: *Unchecked, self: *Self) void {
                if (_InWorld) unchecked.mWorld.Enter(ObjManager(self)) else self.mECSManager.EnterSystem(&unchecked.mOwn);
            }

            fn Leave(unchecked: *Unchecked, self: *Self) void {
                if (_InWorld) unchecked.mWorld.Leave(ObjManager(self)) else self.mECSManager.LeaveSystem(&unchecked.mOwn);
            }
        };

        fn ObjManager(self: *Self) @FieldType(UnderlyingObj(Self), "mManager") {
            if (Self == AManager or Self == AudioManager or Self == UIManager) {
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
            //building an object is structural, governed by the locks, not by what a system around it listed
            var unchecked: Unchecked = .{};
            unchecked.Enter(self);
            defer unchecked.Leave(self);

            const new_obj: UnderlyingObj(Self) = .{ .mID = try self.mECSManager.CreateEntity(engine_context.EngineAllocator()), .mManager = ObjManager(self) };
            try self.ApplyConfig(engine_context, new_obj.mID, config);
            return new_obj;
        }

        /// Deletes the object, and everything under it, right away (see ECSManager.DestroyEntity for when it waits).
        /// A scene takes its entities along. A voice and a UI element are still queued for the end of the frame, for
        /// their managers to delete there. Deleting an object that is already gone does nothing.
        pub fn DeleteObj(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) !void {
            if (!self.mECSManager.IsActiveEntity(obj_id)) return;

            //deleting is structural, governed by the locks, not by what a system around it listed
            var unchecked: Unchecked = .{};
            unchecked.Enter(self);
            defer unchecked.Leave(self);

            if (Self == EManager or Self == GCManager or Self == PManager) {
                return try self.mECSManager.DestroyEntity(engine_context, obj_id);
            }
            if (Self == SManager) {
                return try self.DestroyScene(engine_context, .{ .mID = obj_id, .mManager = ObjManager(self) });
            }

            const obj: UnderlyingObj(Self) = .{ .mID = obj_id, .mManager = ObjManager(self) };
            const event: Self.EventManagerT.EventType = if (Self == AudioManager)
                .{ .DestroyVoice = .{ .Voice = obj } }
            else if (Self == UIManager)
                .{ .DestroyUIElement = .{ .Element = obj } }
            else
                @compileError(std.fmt.comptimePrint("DeleteObj is not implemented for {s} yet", .{@typeName(Self)}));

            for (self.mEventManager.mEventsArray.getPtr(.EndOfFrame).items) |queued_event| {
                if (std.meta.eql(queued_event, event)) return;
            }
            try self.mEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, event);
        }

        /// The ECS's removal hook (see ECSManager.RemovalHook): hands each removal and destroy to OnComponentRemoved or
        /// OnObjectDestroyed, just before it happens
        fn OnECSRemoval(ctx: *anyopaque, engine_context: *EngineContext, event: Self.ECSManagerT.ECSEventDataT.EventT) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            switch (event) {
                .RemoveComponent => |e| try OnComponentRemoved(self, engine_context, e.mEntityID, e.mComponentInd),
                .DestroyEntity => |e| try OnObjectDestroyed(self, engine_context, e.mEntityID),
                else => {},
            }
        }

        /// What taking a component off an object sets off, run just before it comes off, so it can still be read. Every
        /// route a removal comes by ends here, made right away or drained from the ECS's queue.
        /// anyerror because what it removes comes back here
        pub fn OnComponentRemoved(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), component_ind: usize) anyerror!void {
            if (comptime Self == EManager) {
                const entity: Entity = .{ .mID = obj_id, .mManager = ObjManager(self) };

                //the body type tag describes the rigid body, so it goes with it
                if (component_ind == Self.ECSManagerT.ComponentInd(RigidBodyComponent)) try entity.ClearBodyTags(engine_context);

                //a styled entity is restyled when one of its state tags comes off, so the style pass after sees it gone
                if (_IsStateTagInd(component_ind)) try MarkStyleDirty(engine_context, entity, component_ind);

                //the layout trees it leaves, or fits differently in
                try LayoutSystem.OnComponentRemoved(engine_context, entity, component_ind);
            }
        }

        /// What destroying an object sets off, run just before it goes, for it and for each thing under it (children
        /// and scripts go first). Every route a destroy comes by ends here.
        /// anyerror because what it deletes comes back here
        pub fn OnObjectDestroyed(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) anyerror!void {
            //out of the UUID map, if the map points at this object: only that one owns the entry
            if (comptime _HasComponentType(UUIDComponent)) {
                if (self.mECSManager.GetComponent(UUIDComponent, obj_id)) |uuid_component| {
                    if (self.GetWorldID(uuid_component.ID) == obj_id) self.RemoveUUID(uuid_component.ID);
                }
            }

            if (comptime Self == EManager) {
                const entity: Entity = .{ .mID = obj_id, .mManager = ObjManager(self) };
                try LayoutSystem.OnEntityDestroyed(engine_context, entity);
            }
        }

        fn _HasComponentType(comptime component_type: type) bool {
            for (Self.ECSManagerT.ComponentTypes) |list_type| {
                if (list_type == component_type) return true;
            }
            return false;
        }

        pub fn CreateChild(self: *Self, engine_context: *EngineContext, parent_id: UnderlyingObjType(Self), child_type: ECSManager.ChildType, config: UnderlyingObj(Self).CreateConfig) !UnderlyingObj(Self) {
            var unchecked: Unchecked = .{};
            unchecked.Enter(self);
            defer unchecked.Leave(self);
            const new_child: UnderlyingObj(Self) = .{ .mID = try self.mECSManager.AddChild(engine_context, parent_id, child_type), .mManager = ObjManager(self) };
            try self.ApplyConfig(engine_context, new_child.mID, config);
            return new_child;
        }

        /// Adds the component, staged if its type is locked (see ECSManager.AddComponent), and sets off what adding it
        /// does (OnComponentAdded) right away. Returns the staged copy for a staged one
        pub fn AddComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), new_component: anytype) !*@TypeOf(new_component) {
            const component_t = @TypeOf(new_component);
            _ = try self.mECSManager.AddComponent(engine_context, obj_id, new_component);
            try OnComponentAdded(self, engine_context, obj_id, Self.ECSManagerT.ComponentInd(component_t));
            //fetched again: what OnComponentAdded adds can move a component that went on right away
            return self.mECSManager.GetAddedComponent(component_t, obj_id).?;
        }

        /// Adds the component now, see ECSManager.AddComponentSync for when that is safe, and runs OnComponentAdded
        /// for it before returning
        pub fn AddComponentSync(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), new_component: anytype) !*@TypeOf(new_component) {
            const component_t = @TypeOf(new_component);
            _ = try self.mECSManager.AddComponentSync(engine_context, obj_id, new_component);
            try OnComponentAdded(self, engine_context, obj_id, Self.ECSManagerT.ComponentInd(component_t));
            //fetched again: what OnComponentAdded adds can move it
            return self.mECSManager.GetComponent(component_t, obj_id).?;
        }

        /// What adding a component to an object sets off, run by AddComponent and AddComponentSync as soon as the
        /// component is added. Every route a component comes in by ends in one of the two (code, the components panel,
        /// a file, a template), so none of them has to remember any of this. A staged component reads as on its object
        /// (see ECSManager.AddComponent), so all of it can read the component it is about either way.
        /// anyerror because it adds components through AddComponent, which comes back here
        pub fn OnComponentAdded(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), component_ind: usize) anyerror!void {
            //bookkeeping, not the work of a system it might run inside
            var unchecked: Unchecked = .{};
            unchecked.Enter(self);
            defer unchecked.Leave(self);

            const ECSManagerT = Self.ECSManagerT;

            if (comptime Self == EManager) {
                const entity: Entity = .{ .mID = obj_id, .mManager = ObjManager(self) };

                //a transform that has just been added has never been through a transform pass, so its
                //world values are still the InternalData defaults. Those defaults only happen to be
                //right for a root sitting at the origin: a child needs the pass to pick up its parent's
                //world transform, or it renders at the origin at its own local size
                if (component_ind == ECSManagerT.ComponentInd(EntityTransformComponent)) {
                    if (!self.mECSManager.HasComponent(TransformDirtyTag, obj_id)) {
                        _ = try self.mECSManager.AddComponentSync(engine_context, obj_id, TransformDirtyTag{});
                    }
                }

                //what a layout tree is laid out from: the settings, and the text a leaf fits to. On an entity that
                //isn't in any layout the tag is just cleared by the next layout pass
                if (component_ind == ECSManagerT.ComponentInd(LayoutComponent) or
                    component_ind == ECSManagerT.ComponentInd(LayoutItemComponent) or
                    component_ind == ECSManagerT.ComponentInd(TextComponent))
                {
                    try entity.MarkLayoutDirty(engine_context);
                }

                //what a style reads: the state tags, and the parts it colors. A styled entity is restyled only when
                //one of these comes or goes (see StyleSystem)
                if (_IsStateTagInd(component_ind) or
                    component_ind == ECSManagerT.ComponentInd(ShapeComponent) or
                    component_ind == ECSManagerT.ComponentInd(SurfaceComponent) or
                    component_ind == ECSManagerT.ComponentInd(TextComponent))
                {
                    try MarkStyleDirty(engine_context, entity, component_ind);
                }

                //an entity taking a UI element: a new one if the component came without, and either way pointed back
                //at the entity
                if (component_ind == ECSManagerT.ComponentInd(UIElementComponent)) {
                    try engine_context.mUIManager.Adopt(engine_context, entity);
                }

                //a new rigid body gets a type tag if it has none, and its mass and inverse mass put in step with it
                if (component_ind == ECSManagerT.ComponentInd(RigidBodyComponent)) {
                    try entity.SyncRigidBody(engine_context);
                }

                //a body type tag replaces the type the body had, see Entity.OnBodyTypeTagAdded
                inline for (Entity.BodyTypeTags) |tag_type| {
                    if (component_ind == ECSManagerT.ComponentInd(tag_type)) try entity.OnBodyTypeTagAdded(engine_context, tag_type);
                }
            }

            //a UI element's component may need another to go with it, e.g. a scroll needs a scroll state
            if (comptime Self == UIManager) try self.OnElementComponentAdded(engine_context, obj_id, component_ind);
        }

        fn _IsStateTagInd(component_ind: usize) bool {
            inline for (StyleSystem.StateTags) |tag_type| {
                if (component_ind == Self.ECSManagerT.ComponentInd(tag_type)) return true;
            }
            return false;
        }

        /// Takes the component off, right away unless it has to wait (see ECSManager.Lock); OnComponentRemoved runs just
        /// before it does
        pub fn RemoveComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), comptime component_type: type) !void {
            try self.mECSManager.RemoveComponent(engine_context, obj_id, @TypeOf(self.mECSManager).ComponentInd(component_type));
        }

        /// Immediate counterpart to RemoveComponent; see ECSManager.RemoveComponentSync for when
        /// it is safe to use.
        pub fn RemoveComponentSync(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), comptime component_type: type) !void {
            try self.mECSManager.RemoveComponentSync(engine_context, obj_id, @TypeOf(self.mECSManager).ComponentInd(component_type));
        }

        /// A styled entity restyled after the component in `component_ind` came or went: it alone, or everything
        /// inside it too for DisabledTag, which they all show
        fn MarkStyleDirty(engine_context: *EngineContext, entity: Entity, component_ind: usize) !void {
            if (component_ind == Self.ECSManagerT.ComponentInd(DisabledTag)) {
                try engine_context.mUIManager.MarkStyleDirtyTree(engine_context, entity);
            } else {
                try engine_context.mUIManager.MarkStyleDirty(engine_context, entity);
            }
        }

        pub fn GetComponent(self: *Self, component_type: type, obj_id: UnderlyingObjType(Self)) ?*const component_type {
            return self.mECSManager.GetComponent(component_type, obj_id);
        }

        /// GetComponent for changing it: a running system has to list `component_type` in its Writes
        pub fn GetComponentMut(self: *Self, component_type: type, obj_id: UnderlyingObjType(Self)) ?*component_type {
            return self.mECSManager.GetComponentMut(component_type, obj_id);
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
        pub fn LoadObject(self: *Self, engine_context: *EngineContext, rel_path: []const u8, path_type: AManager.PathType) !UnderlyingObj(Self) {
            if (Self == EManager) @compileError("an entity has to belong to a scene, load it with Scene.LoadEntity");
            const new_obj = try CreateObj(self, engine_context, UnderlyingObj(Self).BlankConfig);
            try engine_context.mSerializer.DeserializeECSObj(engine_context, new_obj, rel_path, path_type, .Text);
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
            } else if (manager_t == UIManager) {
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
            } else if (manager_t == UIManager) {
                return UIElement;
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
            } else if (manager_t == UIManager) {
                return UIElement.Type;
            } else {
                @compileError("Not a valid manager type!");
            }
        }
    };
}
