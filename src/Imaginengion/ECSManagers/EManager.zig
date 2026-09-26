const std = @import("std");

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const EventData = @import("../Events/EManagerData.zig");
const ECSEventData = @import("../Events/ECSEventData.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityComponentsList = EntityComponents.ComponentsList;
const NameComponent = EntityComponents.NameComponent;
const UUIDComponent = EntityComponents.UUIDComponent;
const TransformComponent = EntityComponents.TransformComponent;
const ECSCore = @import("Manager.zig").Core;

const EngineContext = @import("../Core/EngineContext.zig");

pub const ECSManagerT = ECSManager(Entity.Type, &EntityComponentsList, "EntityECS");
pub const EventManagerT = EventManager.EventManager(EventData);

const EManager = @This();

const Core = ECSCore(EManager);

pub const empty: EManager = .{
    .mECSManager = .empty,
    .mEventManager = .empty,
    .mUUIDToWorldID = .empty,
};

mECSManager: ECSManagerT,
mEventManager: EventManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, Entity.Type),

pub const Init = Core.Init;

pub const SetSyncCallback = Core.SetSyncCallback;

pub const Deinit = Core.Deinit;

pub const CreateEntity = Core.CreateObj;

pub const DeleteEntity = Core.DeleteObj;

pub const CreateChild = Core.CreateChild;

pub const Duplicate = Core.Duplicate;

pub const AddComponent = Core.AddComponent;

pub const GetComponent = Core.GetComponent;

pub const RemoveComponent = Core.RemoveComponent;
pub const RemoveComponentSync = Core.RemoveComponentSync;

pub const HasComponent = Core.HasComponent;

pub const IsActiveObj = Core.IsActiveObj;

pub const SaveEntity = Core.SaveObject;

pub const SaveEntityAs = Core.SaveObjectAs;

pub const LoadEntity = Core.LoadObject;

pub const GetGroup = Core.GetGroup;

pub const AddUUID = Core.AddUUID;

pub const RemoveUUID = Core.RemoveUUID;

pub const GetWorldID = Core.GetWorldID;

pub const clearAndFree = Core.clearAndFree;

pub const Copy = Core.Copy;

pub fn ProcessEvents(self: *EManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: *std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        var callback = EventManagerT.EventCallback{
            .mCtx = self,
            .mCallbackFn = struct {
                fn thunk(ctx: *anyopaque, ec: *EngineContext, event: *const event_data.EventT) anyerror!EventResult {
                    return @as(*EManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event.*);
                }
            }.thunk,
        };
        //the list belongs to the caller, so ours comes off again on the way out
        callback_list.append(&callback.mNode);
        defer callback_list.remove(&callback.mNode);
        try self.mEventManager.ProcessCategory(event_category, engine_context, callback_list.*);
        self.mEventManager.ClearCategory(engine_context.EngineAllocator(), event_category, .ClearRetainingCapacity);
    } else if (event_data == ECSEventData) {
        var uuid_callback = ECSManagerT.ECSEventCallback{ .mCtx = self, .mCallbackFn = Core.RemoveDestroyedUUID };
        callback_list.append(&uuid_callback.mNode);
        defer callback_list.remove(&uuid_callback.mNode);
        try self.mECSManager.ProcessEvents(engine_context, event_category, callback_list);
    } else {
        std.log.err("EManager.ProcessEvents does not currently handle processing events of type {s}", .{@typeName(event_data)});
    }
}

pub fn OnManagerEvents(self: *EManager, engine_context: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        //the ECS queues the entity's children and scripts along with it
        .DestroyEntity => |e| try self.mECSManager.DestroyEntity(engine_context, e.Entity.mID),
        .Default => unreachable,
    }
    return .Continue;
}

pub fn ApplyConfig(self: *EManager, engine_context: *EngineContext, entity_id: Entity.Type, config: Entity.CreateConfig) !void {
    if (config.bAddName) {
        var name_component: NameComponent = .empty;
        try name_component.mName.appendSlice(engine_context.EngineAllocator(), "New Entity");
        _ = try self.AddComponent(engine_context, entity_id, name_component);
    }
    if (config.bAddUUID) {
        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
        const new_random = io_source.interface();
        const new_uuid_component = try self.AddComponent(engine_context, entity_id, UUIDComponent{ .ID = new_random.int(u64) });
        try self.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, entity_id);
    }
    if (config.bAddTransform) {
        _ = try self.AddComponent(engine_context, entity_id, TransformComponent.empty);
    }
}
