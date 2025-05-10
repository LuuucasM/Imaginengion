const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").ComponentArray;

const VTab = struct {
    Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
    DuplicateEntity: *const fn (*anyopaque, u32, u32) void,
    HasComponent: *const fn (*anyopaque, u32) bool,
    RemoveComponent: *const fn (*anyopaque, u32) anyerror!void,
    clearAndFree: *const fn (*anyopaque) void,
};

pub fn ComponentArray(entity_t: type) type {
    return struct {
        const Self = @This();
        mPtr: *anyopaque,
        mVtable: *const VTab,
        mAllocator: std.mem.Allocator,

        pub fn Init(allocator: std.mem.Allocator, comptime component_type: type) !Self {
            const internal_type = InternalComponentArray(entity_t, component_type);

            const impl = struct {
                fn Deinit(ptr: *anyopaque, deinit_allocator: std.mem.Allocator) void {
                    const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
                    self.Deinit();
                    deinit_allocator.destroy(self);
                }
                fn DuplicateEntity(ptr: *anyopaque, original_entity_id: entity_t, new_entity_id: entity_t) void {
                    const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
                    self.DuplicateEntity(original_entity_id, new_entity_id);
                }
                fn HasComponent(ptr: *anyopaque, entityID: entity_t) bool {
                    const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
                    return self.HasComponent(entityID);
                }
                fn RemoveComponent(ptr: *anyopaque, entityID: entity_t) anyerror!void {
                    const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
                    try self.RemoveComponent(entityID);
                }
                fn clearAndFree(ptr: *anyopaque) void {
                    const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
                    self.clearAndFree();
                }
            };

            const new_component_array = try allocator.create(internal_type);
            new_component_array.* = try internal_type.Init(allocator);

            return Self{
                .mPtr = new_component_array,
                .mVtable = &.{
                    .Deinit = impl.Deinit,
                    .DuplicateEntity = impl.DuplicateEntity,
                    .HasComponent = impl.HasComponent,
                    .RemoveComponent = impl.RemoveComponent,
                    .clearAndFree = impl.clearAndFree,
                },
                .mAllocator = allocator,
            };
        }

        pub fn Deinit(self: Self) void {
            self.mVtable.Deinit(self.mPtr, self.mAllocator);
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
        pub fn clearAndFree(self: Self) void {
            self.mVtable.clearAndFree(self.mPtr);
        }
    };
}
