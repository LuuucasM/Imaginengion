const std = @import("std");

const ResolveReq = @import("../Serializer/Serializer.zig").ResolveReq;

const ECSManager = @import("../ECS/ECSManager.zig").ECSManager;

const Entity = @import("../ECSObjects/Entity.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntityComponentsList = EntityComponents.ComponentsList;
const ECSCore = @import("ECSManager.zig").Core;

const EngineContext = @import("../Core/EngineContext.zig");

pub const ECSManagerE = ECSManager(Entity.Type, &EntityComponentsList);

const EManager = @This();

const Core = ECSCore(EManager);

pub const empty: EManager = .{
    .mECSManager = .empty,
    .mUUIDToWorldID = .empty,
    .mResolveUUIDList = .empty,
};

mECSManager: ECSManagerE,

mUUIDToWorldID: std.AutoHashMapUnmanaged(u64, usize),
mResolveUUIDList: std.ArrayList(ResolveReq),

pub const Init = Core.Init;
pub const Deinit = Core.Deinit;

pub fn SaveEntity(self: *EManager, engine_context: *EngineContext, entity: Entity) !void {}

pub fn SaveEntityAs(_: *EManager, engine_context: *EngineContext, entity: Entity) !void {}

pub fn GetGroup(self: *EManager, frame_allocator: std.mem.Allocator, query: GroupQuery) !std.ArrayList(Entity.Type) {}

pub fn AddUUID(self: *EManager, engine_allocator: std.mem.Allocator, uuid: u64, world_id: usize) !void {}

pub fn RemoveUUID(self: *EManager, uuid: u64) void {}

pub fn GetWorldID(self: EManager, uuid: u64) ?usize {}

pub fn AddResolveUUID(self: *EManager, engine_allocator: std.mem.Allocator, resolve_req: ResolveReq) !void {}
pub fn clearAndFree(self: *EManager, engine_context: *EngineContext) !void {}

pub fn RmEntityComp(self: *EManager, engine_allocator: std.mem.Allocator, scene_id: Entity.Type, component_ind: EEntityComponents) !void {}

pub fn ProcessEvents(self: *EManager, engine_context: *EngineContext, event_type: EventType) !void {}

pub fn Copy(self: *EManager, engine_context: *EngineContext, other_scene: *EManager) !void {}

pub fn EntityECSCallback(scene_manager: *anyopaque, _: *EngineContext, event: ECSManagerE.ECSEventManager.EventType) anyerror!bool {
    const self: *EManager = @ptrCast(@alignCast(scene_manager));
    switch (event) {
        .DestroyEntity => |e| {
            const entity = self.GetEntity(e.mEntityID);
            self.RemoveUUID(entity.GetUUID());
        },
        .RemoveComponent => |e| {
            const entity = self.GetEntity(e.mEntityID);
            if (e.mComponentInd == EntityUUIDComponent.Ind) {
                self.RemoveUUID(entity.GetUUID());
            }
        },
        .Default => {
            @panic("this musnt happen\n");
        },
    }
    return true;
}
