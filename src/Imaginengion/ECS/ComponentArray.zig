const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").InternalComponentArray;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn ComponentArray(entity_t: type) type {
    const VTab = struct {
        CopyInto: *const fn (*anyopaque, *EngineContext, *anyopaque) anyerror!void,
        DeinitComponents: *const fn (*anyopaque, *EngineContext) void,
        Deinit: *const fn (*anyopaque, *EngineContext) void,
        StageDuplicate: *const fn (*anyopaque, *EngineContext, std.mem.Allocator, entity_t) anyerror!*anyopaque,
        HasComponent: *const fn (*anyopaque, entity_t) bool,
        RemoveComponent: *const fn (*anyopaque, *EngineContext, entity_t) void,
        clearAndFree: *const fn (*anyopaque, *EngineContext) void,
        DestroyEntity: *const fn (*anyopaque, *EngineContext, entity_t) void,
        AddStaged: *const fn (*anyopaque, std.mem.Allocator, entity_t, *anyopaque) anyerror!void,
        DeinitStaged: *const fn (*EngineContext, *anyopaque) void,
        CloneStaged: *const fn (*EngineContext, std.mem.Allocator, *const anyopaque) anyerror!*anyopaque,
    };
    return struct {
        const Self = @This();

        mPtr: *anyopaque,
        mVtable: *const VTab,
        /// zero sized: a tag, with no value to lose when one is added twice
        mIsTag: bool,

        pub fn Init(engine_allocator: std.mem.Allocator, comptime component_type: type) !Self {
            const internal_type = InternalComponentArray(entity_t, component_type);
            const impl = struct {
                fn CopyInto(ptr: *anyopaque, engine_context: *EngineContext, other_ptr: *anyopaque) anyerror!void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    const other = @as(*internal_type, @ptrCast(@alignCast(other_ptr)));
                    try self.CopyInto(engine_context, other);
                }
                fn DeinitComponents(ptr: *anyopaque, engine_context: *EngineContext) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.DeinitComponents(engine_context);
                }
                fn Deinit(ptr: *anyopaque, engine_context: *EngineContext) void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    self.Deinit(engine_context);
                    engine_context.EngineAllocator().destroy(self);
                }
                fn StageDuplicate(ptr: *anyopaque, engine_context: *EngineContext, arena: std.mem.Allocator, original_entity_id: entity_t) anyerror!*anyopaque {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    return try self.StageDuplicate(engine_context, arena, original_entity_id);
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
                fn AddStaged(ptr: *anyopaque, allocator: std.mem.Allocator, entity_id: entity_t, staged: *anyopaque) anyerror!void {
                    const self = @as(*internal_type, @ptrCast(@alignCast(ptr)));
                    try self.AddStaged(allocator, entity_id, staged);
                }
                fn DeinitStaged(engine_context: *EngineContext, staged: *anyopaque) void {
                    internal_type.DeinitStaged(engine_context, staged);
                }
                fn CloneStaged(engine_context: *EngineContext, arena: std.mem.Allocator, source: *const anyopaque) anyerror!*anyopaque {
                    return try internal_type.CloneStaged(engine_context, arena, source);
                }
            };

            const new_component_array = try engine_allocator.create(internal_type);
            new_component_array.* = .{};

            return Self{
                .mPtr = new_component_array,
                .mIsTag = @sizeOf(component_type) == 0,
                .mVtable = &.{
                    .CopyInto = impl.CopyInto,
                    .DeinitComponents = impl.DeinitComponents,
                    .Deinit = impl.Deinit,
                    .StageDuplicate = impl.StageDuplicate,
                    .HasComponent = impl.HasComponent,
                    .RemoveComponent = impl.RemoveComponent,
                    .clearAndFree = impl.clearAndFree,
                    .DestroyEntity = impl.DestroyEntity,
                    .AddStaged = impl.AddStaged,
                    .DeinitStaged = impl.DeinitStaged,
                    .CloneStaged = impl.CloneStaged,
                },
            };
        }

        /// `other` has to be the array at the same index of another ComponentManager, so that both
        /// hold the same component type behind their erased pointers.
        pub fn CopyInto(self: Self, engine_context: *EngineContext, other: Self) anyerror!void {
            try self.mVtable.CopyInto(self.mPtr, engine_context, other.mPtr);
        }
        /// Runs every component's Deinit, leaving the storage in place
        pub fn DeinitComponents(self: Self, engine_context: *EngineContext) void {
            self.mVtable.DeinitComponents(self.mPtr, engine_context);
        }
        /// Frees the storage and the array itself, DeinitComponents has to have run first
        pub fn Deinit(self: Self, engine_context: *EngineContext) void {
            self.mVtable.Deinit(self.mPtr, engine_context);
        }
        /// A copy of the entity's component in `arena`, cloned if the type has a Clone
        pub fn StageDuplicate(self: Self, engine_context: *EngineContext, arena: std.mem.Allocator, original_entity_id: entity_t) anyerror!*anyopaque {
            return try self.mVtable.StageDuplicate(self.mPtr, engine_context, arena, original_entity_id);
        }
        pub fn RemoveComponent(self: Self, engine_context: *EngineContext, entityID: entity_t) void {
            self.mVtable.RemoveComponent(self.mPtr, engine_context, entityID);
        }
        pub fn HasComponent(self: Self, entityID: entity_t) bool {
            return self.mVtable.HasComponent(self.mPtr, entityID);
        }
        /// Frees the storage, DeinitComponents has to have run first
        pub fn clearAndFree(self: Self, engine_context: *EngineContext) void {
            self.mVtable.clearAndFree(self.mPtr, engine_context);
        }
        pub fn DestroyEntity(self: Self, engine_context: *EngineContext, entity_id: entity_t) void {
            self.mVtable.DestroyEntity(self.mPtr, engine_context, entity_id);
        }
        /// Copies a staged component (see ECSManager.AddComponent) onto the entity. `staged` has to point at a
        /// value of this array's component type.
        pub fn AddStaged(self: Self, engine_allocator: std.mem.Allocator, entity_id: entity_t, staged: *anyopaque) anyerror!void {
            try self.mVtable.AddStaged(self.mPtr, engine_allocator, entity_id, staged);
        }
        /// Deinitializes a staged component that will never be added. `staged` has to point at a value of this
        /// array's component type.
        pub fn DeinitStaged(self: Self, engine_context: *EngineContext, staged: *anyopaque) void {
            self.mVtable.DeinitStaged(engine_context, staged);
        }
        /// A copy of a staged component in `arena`, cloned if the type has a Clone. `source` has to point at a value
        /// of this array's component type.
        pub fn CloneStaged(self: Self, engine_context: *EngineContext, arena: std.mem.Allocator, source: *const anyopaque) anyerror!*anyopaque {
            return try self.mVtable.CloneStaged(engine_context, arena, source);
        }
    };
}
