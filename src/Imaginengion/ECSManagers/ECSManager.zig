const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");

const AManager = @import("AManager.zig");
const EManager = @import("EManager.zig");
const GCManager = @import("GCManager.zig");
const PManager = @import("PManager.zig");
const SManager = @import("SManager.zig");

const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const Player = @import("../ECSObjects/Player.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const Serializer = @import("../Serializer/Serializer.zig");
const ResolveReq = Serializer.ResolveReq;

const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;

pub fn Core(comptime Self: type) type {
    return struct {
        comptime {
            _ValidateObject(Self);
        }

        pub fn Init(self: Self, engine_allocator: std.mem.Allocator) !void {
            try self.mECSManager.Init(engine_allocator);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            try self.mECSManager.Deinit(engine_context.EngineAllocator());
            self.mUUIDToWorldID.deinit(engine_context.EngineAllocator());
            self.mResolveUUIDList.deinit(engine_context.EngineAllocator());
            self.mEventManager.Deinit(engine_context.EngineAllocator());
        }

        pub fn CreateObj(self: *Self, engine_context: *EngineContext, config: UnderlyingObj(Self).CreateConfig) !UnderlyingObj(Self) {
            //TODO
        }

        pub fn DeleteObj(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) !void {
            //TODO
        }

        pub fn Duplicate(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self)) UnderlyingObj(Self) {
            //TODO
        }

        pub fn AddComponent(self: *Self, engine_context: *EngineContext, obj_id: UnderlyingObjType(Self), new_component: anytype) !*@TypeOf(new_component) {
            return try self.mECSManager.AddComponent(engine_context.EngineAllocator(), obj_id, new_component);
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
            engine_context.mSerializer.SaveECSObject(engine_context, object);
        }

        pub fn SaveObjectAs(_: *Self, engine_context: *EngineContext, object: UnderlyingObj(Self)) !void {
            engine_context.mSerializer.SaveECSObjAs(engine_context, object);
        }

        pub fn GetGroup(self: *Self, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(UnderlyingObjType(Self)) {
            return self.mECSManager.GetGroup(frame_allocator, query);
        }

        pub fn ProcessEvents(self: *Self, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
            if (event_data == Self.EventData) {
                const callback = Self.EventManagerT.EventCallback{
                    .mCtx = self,
                    .mCallbackFn = struct {
                        fn thunk(ctx: *anyopaque, ec: *EngineContext, event: event_data.EventT) anyerror!EventResult {
                            return @as(EManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event);
                        }
                    }.thunk,
                };
                callback_list.append(&callback.mNode);
                self.mEventManager.ProcessCategory(event_category, engine_context, callback_list);
            } else {
                std.log.err("EManager.ProcessEvents does not currently handle processing events of type {s}", @typeName(event_data));
            }
        }

        pub fn clearAndFree(self: *Self, engine_context: *EngineContext) void {
            self.mECSManager.clearAndFree(engine_context);
            self.mUUIDToWorldID.clearAndFree(engine_context.EngineAllocator());
            self.mResolveUUIDList.deinit(engine_context.EngineAllocator());
            self.mEventManager.EventsReset(engine_context.EngineAllocator(), .ClearAndFree);
        }

        //pub fn Copy(self: *AManager, engine_context: *EngineContext, other_scene: *AManager) !void {}

        pub fn AddUUID(self: *Self, engine_allocator: std.mem.Allocator, uuid: u64, world_id: Self.WorldIDT) !void {
            try self.mUUIDToWlrdID.put(engine_allocator, uuid, world_id);
        }

        pub fn RemoveUUID(self: *AManager, uuid: u64) void {
            _ = self.mUUIDToWorldID.remove(uuid);
        }

        pub fn GetWorldID(self: *AManager, uuid: u64) ?UnderlyingObjType(Self) {
            return self.mUUIDToWorldID.get(uuid);
        }

        pub fn AddResolveUUID(self: *AManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {
            try self.mResolveUUIDList.append(engine_allocator, resolve_req);
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
