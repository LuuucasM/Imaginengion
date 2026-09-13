const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const EventData = @import("../Events/EManagerData.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityComponentsList = EntityComponents.ComponentsList;
const ECSCore = @import("ECSManager.zig").Core;

const EngineContext = @import("../Core/EngineContext.zig");

pub const ECSManagerT = ECSManager(Entity.Type, &EntityComponentsList);
pub const EventManagerT = EventManager.EventManager(EventData);

const EManager = @This();

const Core = ECSCore(EManager);

pub const empty: EManager = .{
    .mECSManager = .empty,
    .mUUIDToWorldID = .empty,
    .mResolveUUIDList = .empty,
};

mECSManager: ECSManagerT,
mEventManager: EventManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize),
mResolveUUIDList: std.ArrayList(ResolveReq),

pub const Init = Core.Init;

pub const Deinit = Core.Deinit;

pub const CreateEntity = Core.CreateObj;

pub const DeleteEntity = Core.DeleteObj;

pub const CreateChild = Core.CreateChild;

pub const Duplicate = Core.Duplicate;

pub const AddComponent = Core.AddComponent;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const IsActiveEntity = Core.IsActiveObj;

pub const SaveEntity = Core.SaveObject;

pub const SaveEntityAs = Core.SaveObjectAs;

pub const GetGroup = Core.GetGroup;

pub const AddUUID = Core.AddUUID;

pub const RemoveUUID = Core.RemoveUUID;

pub const GetWorldID = Core.GetWorldID;

pub const AddResolveUUID = Core.AddResolveUUID;

pub const clearAndFree = Core.clearAndFree;

pub fn ProcessEvents(self: *EManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        const callback = EventManagerT.EventCallback{
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

pub fn OnManagerEvents(_: *EManager, _: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .Default => unreachable,
    }
    return .Continue;
}
