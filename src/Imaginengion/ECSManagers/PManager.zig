const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;
const EventManager = @import("../Events/EventManager.zig");
const EventResult = EventManager.EventResult;
const EventData = @import("../Events/PManagerData.zig");

const Player = @import("../ECSObjects/Player.zig");
const PComponents = @import("../ECSComponents/PComponents.zig");
const PComponentsList = PComponents.ComponentsList;
const ECSCore = @import("ECSManager.zig").Core;

const EngineContext = @import("../Core/EngineContext.zig");

pub const ECSManagerT = ECSManager(Player.Type, &PComponentsList);
pub const EventManagerT = EventManager.EventManager(EventData);

const PManager = @This();

const Core = ECSCore(PManager);

pub const empty: PManager = .{
    .mECSmanager = .empty,
    .mEventManager = .empty,
    .mUUIDToWorldID = .empty,
    .mResolveUUIDList = .empty,
};

mECSManager: ECSManagerT,
mEventManager: EventManagerT,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, Player.Type),
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

pub const RemoveUUID = Core.RemoveUUID;

pub const SaveObject = Core.SaveObject;

pub const SaveObjectAs = Core.SaveObjectAs;

pub fn ProcessEvents(self: *PManager, comptime event_data: type, comptime event_category: event_data.EventCategories, engine_context: *EngineContext, callback_list: std.DoublyLinkedList) !void {
    if (event_data == EventData) {
        const callback = EventManagerT.EventCallback{
            .mCtx = self,
            .mCallbackFn = struct {
                fn thunk(ctx: *anyopaque, ec: *EngineContext, event: event_data.EventT) anyerror!EventResult {
                    return @as(PManager, @ptrCast(@alignCast(ctx))).OnManagerEvents(ec, event);
                }
            }.thunk,
        };
        callback_list.append(&callback.mNode);
        self.mEventManager.ProcessCategory(event_category, engine_context, callback_list);
    } else {
        std.log.err("PManager.ProcessEvents does not currently handle processing events of type {s}", @typeName(event_data));
    }
}

pub fn ProcessConfig(self: PManager, engine_context: *EngineContext, player_id: Player.Type, config: Player.CreateConfig) !void {
    if (config.bAddUUIDComponent) {
        _ = try self.mECSManager.AddComponent(engine_context.EngineAllocator(), player_id, PComponents.UUIDComponent.empty);
    }
    if (config.bAddNameComponent) {
        const name_component = try self.mECSManager.AddComponent(engine_context.EngineAllocator(), player_id, PComponents.NameComponent.empty);
        name_component.mName.appendSlice(engine_context.EngineAllocator(), "New Game Context");
    }
}

pub fn OnManagerEvents(_: *PManager, _: *EngineContext, event: EventData.EventT) anyerror!EventResult {
    switch (event) {
        .Default => unreachable,
    }
    return .Continue;
}
