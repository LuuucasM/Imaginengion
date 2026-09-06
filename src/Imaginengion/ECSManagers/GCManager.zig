const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const EventData = @import("../Events/GCEventData.zig");

const GameContext = @import("../ECSObjects/GameContext.zig");
const GCComponentsList = @import("../ECSComponents/GCComponents.zig").ComponentsList;
const ECSCore = @import("ECSManager.zig").Core;

const EngineContext = @import("../Core/EngineContext.zig");

pub const ECSManagerT = ECSManager(GameContext.Type, &GCComponentsList);
pub const EventManagerT = EventManager.EventManager(EventData);

const GCManager = @This();

const Core = ECSCore(GCManager);

pub const empty: GCManager = .{
    .mECSmanager = .empty,
    .mEventManager = .empty,
    .mUUIDToWorldID = .empty,
    .mResolveUUIDList = .empty,
};

mECSManager: ECSManagerT,
mEventManager: EventManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, GameContext.Type),
mResolveUUIDList: std.ArrayList(ResolveReq),

pub const CreateGameContext = Core.CreateObj;

pub const DeleteGameContext = Core.DeleteObj;

pub const Duplicate = Core.Duplicate;

pub const AddComponent = Core.AddComponent;

pub const AddResolveUUID = Core.AddResolveUUID;

pub const AddUUID = Core.AddUUID;

pub const clearAndFree = Core.clearAndFree;

pub const Deinit = Core.Deinit;

pub const GetComponent = Core.GetComponent;

pub const GetGroup = Core.GetGroup;

pub const GetWorldID = Core.GetWorldID;

pub const HasComponent = Core.HasComponent;

pub const Init = Core.Init;

pub const IsActiveObj = Core.IsActiveObj;

pub const ProcessEvents = Core.ProcessEvents;

pub const RemoveUUID = Core.RemoveUUID;

pub const SaveObject = Core.SaveObject;

pub const SaveObjectAs = Core.SaveObjectAs;

pub fn ProcessConfig(self: GameContext, engine_context: *EngineContext, config: GameContext.CreateConfig) !void {}

pub fn OnManagerEvents(_: *GCManager, _: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .Default => unreachable,
    }
    return .Continue;
}
