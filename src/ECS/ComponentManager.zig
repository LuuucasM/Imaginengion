const std = @import("std");
const IComponentArray = @import("ComponentArray.zig").IComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const ComponentManager = @This();

_ComponentArrays: std.AutoHashMap(type, IComponentArray) = undefined,
_ComponentGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},

pub fn Init(self: ComponentManager) void {
    self._ComponentArrays = std.AutoHashMap(type, IComponentArray).init(self._ComponentGPA.allocator());
}

pub fn Deinit(self: ComponentManager) void {
    self._ComponentArrays.deinit();
}

pub fn RegisterComponent(self: ComponentManager, comptime ComponentType: type) !void {
    const component_array_type = ComponentArray(ComponentType);
    const component_array = try self._ComponentGPA.allocator().create(component_array_type);
    component_array.* = .{};
    component_array.Init(self._ComponentGPA.allocator());
    const i_component_array = .{ .ptr = component_array };
    try self._ComponentArrays.putNoClobber(ComponentType, i_component_array);
}

pub fn AddComponent(self: ComponentManager, comptime ComponentType: type, entityID: u128, component: ComponentType) *ComponentType {
    _ = self;
    _ = entityID;
    _ = component;
}

pub fn RemoveComponent(self: ComponentManager, comptime ComponentType: type, entityID: u128) void {
    _ = self;
    _ = ComponentType;
    _ = entityID;
}

pub fn HasComponent(self: ComponentManager, comptime ComponentType: type, entityID: u128) bool {
    _ = self;
    _ = ComponentType;
    _ = entityID;
}

pub fn GetComponent(self: ComponentManager, comptime ComponentType: type, entityID: u64) *ComponentType {
    _ = self;
    _ = entityID;
}

pub fn GetComponents(self: ComponentManager, comptime ComponentTypes: anytype, entityID: u64) std.meta.Tuple(ComponentTypes) {
    _ = self;
    _ = entityID;
}
