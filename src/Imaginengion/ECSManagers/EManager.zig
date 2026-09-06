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

pub const AddComponent = Core.AddComponent;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const IsActiveEntity = Core.IsActiveObj;

//Create and delete and Add Child and DUplicate functions but not for EManager because SManager holds the lifetime of entities

pub const SaveEntity = Core.SaveObject;

pub const SaveEntityAs = Core.SaveObjectAs;

pub const GetGroup = Core.GetGroup;

pub const AddUUID = Core.AddUUID;

pub const RemoveUUID = Core.RemoveUUID;

pub const GetWorldID = Core.GetWorldID;

pub const AddResolveUUID = Core.AddResolveUUID;

pub const clearAndFree = Core.clearAndFree;

pub const ProcessEvents = Core.ProcessEvents;

pub fn OnManagerEvents(_: *EManager, _: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .Default => unreachable,
    }
    return .Continue;
}
