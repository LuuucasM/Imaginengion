const std = @import("std");
const InternalComponentArray = @import("InternalComponentArray.zig").ComponentArray;
const ComponentArray = @This();

const VTab = struct {
    Deinit: *const fn (*anyopaque, std.mem.Allocator) void,
    DuplicateEntity: *const fn (*anyopaque, u32, u32) void,
    HasComponent: *const fn (*anyopaque, u32) bool,
    RemoveComponent: *const fn (*anyopaque, u32) anyerror!void,
    clearAndFree: *const fn (*anyopaque) void,
};

mPtr: *anyopaque,
mVtable: *const VTab,
mAllocator: std.mem.Allocator,

pub fn Init(allocator: std.mem.Allocator, comptime component_type: type) !ComponentArray {
    const internal_type = InternalComponentArray(component_type);

    const impl = struct {
        fn Deinit(ptr: *anyopaque, deinit_allocator: std.mem.Allocator) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.Deinit();
            deinit_allocator.destroy(self);
        }
        fn DuplicateEntity(ptr: *anyopaque, original_entity_id: u32, new_entity_id: u32) void {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            self.DuplicateEntity(original_entity_id, new_entity_id);
        }
        fn HasComponent(ptr: *anyopaque, entityID: u32) bool {
            const self = @as(*internal_type, @alignCast(@ptrCast(ptr)));
            return self.HasComponent(entityID);
        }
        fn RemoveComponent(ptr: *anyopaque, entityID: u32) anyerror!void {
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

    return ComponentArray{
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

pub fn Deinit(self: ComponentArray) void {
    self.mVtable.Deinit(self.mPtr, self.mAllocator);
}
pub fn DuplicateEntity(self: ComponentArray, original_entity_id: u32, new_entity_id: u32) void {
    self.mVtable.DuplicateEntity(self.mPtr, original_entity_id, new_entity_id);
}
pub fn RemoveComponent(self: ComponentArray, entityID: u32) anyerror!void {
    try self.mVtable.RemoveComponent(self.mPtr, entityID);
}
pub fn HasComponent(self: ComponentArray, entityID: u32) bool {
    return self.mVtable.HasComponent(self.mPtr, entityID);
}
pub fn clearAndFree(self: ComponentArray) void {
    self.mVtable.clearAndFree(self.mPtr);
}
