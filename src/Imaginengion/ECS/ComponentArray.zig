const std = @import("std");
const ComponentCategory = @import("ECSManager.zig").ComponentCategory;
const InternalComponentArray = @import("InternalComponentArray.zig").ComponentArray;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn ComponentArray(entity_t: type) type {
    const ECSEventManager = @import("ECSEventManager.zig").ECSEventManager(entity_t);
    const VTab = struct {
        Deinit: *const fn (*anyopaque, std.mem.Allocator) anyerror!void,
        DuplicateEntity: *const fn (*anyopaque, entity_t, entity_t) void,
        HasComponent: *const fn (*anyopaque, entity_t) bool,
        RemoveComponent: *const fn (*anyopaque, entity_t) anyerror!void,
        clearAndFree: *const fn (*anyopaque, EngineContext) void,
        GetCategory: *const fn (*anyopaque) ComponentCategory,
        DestroyEntity: *const fn (*anyopaque, EngineContext, entity_t, *ECSEventManager) anyerror!void,
        GetMultiData: *const fn (*anyopaque, entity_t) @Vector(4, entity_t),
        SetMultiData: *const fn (*anyopaque, entity_t, @Vector(4, entity_t)) void,
    };
    return struct {
        const Self = @This();

        mPtr: *anyopaque,
        mVtable: *const VTab,

        pub fn Init(engine_allocator: std.mem.Allocator, comptime component_type: type) !Self {
            const internal_type = InternalComponentArray(entity_t, component_type);
            const impl = struct {
                fn Deinit(ptr: *anyopaque, deinit_allocator: std.mem.Allocator) !void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    try self.Deinit();
                    deinit_allocator.destroy(self);
                }
                fn DuplicateEntity(ptr: *anyopaque, original_entity_id: entity_t, new_entity_id: entity_t) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.DuplicateEntity(original_entity_id, new_entity_id);
                }
                fn HasComponent(ptr: *anyopaque, entityID: entity_t) bool {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    return self.HasComponent(entityID);
                }
                fn RemoveComponent(ptr: *anyopaque, entityID: entity_t) anyerror!void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    try self.RemoveComponent(entityID);
                }
                fn clearAndFree(ptr: *anyopaque, engine_context: EngineContext) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.clearAndFree(engine_context);
                }
                fn GetCategory(ptr: *anyopaque) ComponentCategory {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    return self.GetCategory();
                }
                fn DestroyEntity(ptr: *anyopaque, engine_context: EngineContext, entity_id: entity_t, ecs_event_manager: *ECSEventManager) anyerror!void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    try self.DestroyEntity(engine_context, entity_id, ecs_event_manager);
                }
                fn GetMultiData(ptr: *anyopaque, entity_id: entity_t) @Vector(4, entity_t) {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    return self.GetMultiData(entity_id);
                }
                fn SetMultiData(ptr: *anyopaque, entity_id: entity_t, multi_data: @Vector(4, entity_t)) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.SetMultiData(entity_id, multi_data);
                }
            };

            const new_component_array = try engine_allocator.create(internal_type);
            new_component_array.* = try internal_type.Init(engine_allocator);

            return Self{
                .mPtr = new_component_array,
                .mVtable = &.{
                    .Deinit = impl.Deinit,
                    .DuplicateEntity = impl.DuplicateEntity,
                    .HasComponent = impl.HasComponent,
                    .RemoveComponent = impl.RemoveComponent,
                    .clearAndFree = impl.clearAndFree,
                    .GetCategory = impl.GetCategory,
                    .DestroyEntity = impl.DestroyEntity,
                    .GetMultiData = impl.GetMultiData,
                    .SetMultiData = impl.SetMultiData,
                },
            };
        }

        pub fn Deinit(self: Self, engine_allocator: std.mem.Allocator) !void {
            try self.mVtable.Deinit(self.mPtr, engine_allocator);
        }
        pub fn DuplicateEntity(self: Self, original_entity_id: entity_t, new_entity_id: entity_t) void {
            self.mVtable.DuplicateEntity(self.mPtr, original_entity_id, new_entity_id);
        }
        pub fn RemoveComponent(self: Self, entityID: entity_t) anyerror!void {
            try self.mVtable.RemoveComponent(self.mPtr, entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mVtable.HasComponent(self.mPtr, entityID);
        }
        pub fn clearAndFree(self: Self, engine_context: EngineContext) void {
            self.mVtable.clearAndFree(self.mPtr, engine_context);
        }
        pub fn DestroyEntity(self: Self, engine_context: EngineContext, entity_id: entity_t, ecs_event_manager: *ECSEventManager) anyerror!void {
            try self.mVtable.DestroyEntity(self.mPtr, engine_context, entity_id, ecs_event_manager);
        }

        pub fn GetCategory(self: Self) ComponentCategory {
            return self.mVtable.GetCategory(self.mPtr);
        }
        pub fn GetMultiData(self: Self, entity_id: entity_t) @Vector(4, entity_t) {
            return self.mVtable.GetMultiData(self.mPtr, entity_id);
        }
        pub fn SetMultiData(self: Self, entity_id: entity_t, multi_data: @Vector(4, entity_t)) void {
            self.mVtable.SetMultiData(self.mPtr, entity_id, multi_data);
        }
    };
}
