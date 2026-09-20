const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").InternalComponentArray;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn ComponentArray(entity_t: type) type {
    const VTab = struct {
        CopyInto: *const fn (*anyopaque, *EngineContext, *anyopaque) anyerror!void,
        Deinit: *const fn (*anyopaque, *EngineContext) void,
        DuplicateEntity: *const fn (*anyopaque, *EngineContext, entity_t, entity_t) anyerror!void,
        HasComponent: *const fn (*anyopaque, entity_t) bool,
        RemoveComponent: *const fn (*anyopaque, *EngineContext, entity_t) void,
        clearAndFree: *const fn (*anyopaque, *EngineContext) void,
        DestroyEntity: *const fn (*anyopaque, *EngineContext, entity_t) void,
    };
    return struct {
        const Self = @This();

        mPtr: *anyopaque,
        mVtable: *const VTab,

        pub fn Init(engine_allocator: std.mem.Allocator, comptime component_type: type) !Self {
            const internal_type = InternalComponentArray(entity_t, component_type);
            const impl = struct {
                fn CopyInto(ptr: *anyopaque, engine_context: *EngineContext, other_ptr: *anyopaque) anyerror!void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    const other = @as(*internal_type, @ptrCast(@alignCast(other_ptr)));
                    try self.CopyInto(engine_context, other);
                }
                fn Deinit(ptr: *anyopaque, engine_context: *EngineContext) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.Deinit(engine_context);
                    engine_context.EngineAllocator().destroy(self);
                }
                fn DuplicateEntity(ptr: *anyopaque, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) anyerror!void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    try self.DuplicateEntity(engine_context, original_entity_id, new_entity_id);
                }
                fn HasComponent(ptr: *anyopaque, entityID: entity_t) bool {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    return self.HasComponent(entityID);
                }
                fn RemoveComponent(ptr: *anyopaque, engine_context: *EngineContext, entityID: entity_t) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.RemoveComponent(engine_context, entityID);
                }
                fn clearAndFree(ptr: *anyopaque, engine_context: *EngineContext) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.clearAndFree(engine_context);
                }
                fn DestroyEntity(ptr: *anyopaque, engine_context: *EngineContext, entity_id: entity_t) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.DestroyEntity(engine_context, entity_id);
                }
            };

            const new_component_array = try engine_allocator.create(internal_type);
            new_component_array.* = .{};

            return Self{
                .mPtr = new_component_array,
                .mVtable = &.{
                    .CopyInto = impl.CopyInto,
                    .Deinit = impl.Deinit,
                    .DuplicateEntity = impl.DuplicateEntity,
                    .HasComponent = impl.HasComponent,
                    .RemoveComponent = impl.RemoveComponent,
                    .clearAndFree = impl.clearAndFree,
                    .DestroyEntity = impl.DestroyEntity,
                },
            };
        }

        /// `other` has to be the array at the same index of another ComponentManager, so that both
        /// hold the same component type behind their erased pointers.
        pub fn CopyInto(self: Self, engine_context: *EngineContext, other: Self) anyerror!void {
            try self.mVtable.CopyInto(self.mPtr, engine_context, other.mPtr);
        }
        pub fn Deinit(self: Self, engine_context: *EngineContext) void {
            self.mVtable.Deinit(self.mPtr, engine_context);
        }
        pub fn DuplicateEntity(self: Self, engine_context: *EngineContext, original_entity_id: entity_t, new_entity_id: entity_t) anyerror!void {
            try self.mVtable.DuplicateEntity(self.mPtr, engine_context, original_entity_id, new_entity_id);
        }
        pub fn RemoveComponent(self: Self, engine_context: *EngineContext, entityID: entity_t) void {
            self.mVtable.RemoveComponent(self.mPtr, engine_context, entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mVtable.HasComponent(self.mPtr, entityID);
        }
        pub fn clearAndFree(self: Self, engine_context: *EngineContext) void {
            self.mVtable.clearAndFree(self.mPtr, engine_context);
        }
        pub fn DestroyEntity(self: Self, engine_context: *EngineContext, entity_id: entity_t) void {
            self.mVtable.DestroyEntity(self.mPtr, engine_context, entity_id);
        }
    };
}
