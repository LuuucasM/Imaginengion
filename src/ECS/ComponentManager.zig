const std = @import("std");
const IComponentArray = @import("ComponentArray.zig").IComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const Components = @import("Components.zig");
const ComponentsList = Components.ComponentsList;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

const ComponentManager = @This();

pub const BitFieldType: type = std.meta.Int(.unsigned, ComponentsList.len);

_ComponentsArrays: std.ArrayList(IComponentArray) = undefined,
_EntityComponentArrays: SparseSet(.{
    .SparseT = u32,
    .DenseT = u32,
    .ValueT = StaticSkipField(ComponentsList.len),
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
}) = undefined,
_ComponentGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},

pub fn Init(self: *ComponentManager) !void {
    self._ComponentsArrays = std.ArrayList(IComponentArray).init(self._ComponentGPA.allocator());
    self._EntityComponentArrays = try SparseSet(.{
        .SparseT = u32,
        .DenseT = u32,
        .ValueT = StaticSkipField(ComponentsList.len),
        .value_layout = .InternalArrayOfStructs,
        .allow_resize = .ResizeAllowed,
    }).init(self._ComponentGPA.allocator(), 20, 10);

    //init component arrays
    inline for (ComponentsList) |component_type| {
        const component_array = try self._ComponentGPA.allocator().create(ComponentArray(component_type));
        component_array.* = try ComponentArray(component_type).Init(self._ComponentGPA.allocator());

        const i_component_array = IComponentArray.Init(component_array);

        try self._ComponentsArrays.append(i_component_array);
    }
}

pub fn Deinit(self: *ComponentManager) void {
    //delete component arrays
    for (self._ComponentsArrays.items) |component_array| {
        component_array.Deinit(self._ComponentGPA.allocator());
    }

    self._ComponentsArrays.deinit();
    self._EntityComponentArrays.deinit();
    _ = self._ComponentGPA.deinit();
}

pub fn AddComponent(self: *ComponentManager, comptime ComponentType: type, entityID: u32, component: ComponentType) !*ComponentType {
    std.debug.assert(!self.HasComponent(ComponentType, entityID));

    self._EntityComponentArrays.getValueBySparse(entityID).ChangeToUnskipped(ComponentType.Ind);

    return try @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self._ComponentsArrays.items[ComponentType.Ind].ptr))).AddComponent(entityID, component);
}

pub fn RemoveComponent(self: *ComponentManager, comptime ComponentType: type, entityID: u32) !void {
    std.debug.assert(self.HasComponent(ComponentType, entityID));

    self._EntityComponentArrays.getValueBySparse(entityID).ChangeToSkipped(ComponentType.Ind);

    return try self._ComponentsArrays.items[ComponentType.Ind].RemoveComponent(entityID);
}

pub fn HasComponent(self: ComponentManager, comptime ComponentType: type, entityID: u32) bool {
    return @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self._ComponentsArrays.items[ComponentType.Ind].ptr))).HasComponent(entityID);
}

pub fn GetComponent(self: ComponentManager, comptime ComponentType: type, entityID: u32) *ComponentType {
    std.debug.assert(self.HasComponent(ComponentType, entityID));
    return @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self._ComponentsArrays.items[ComponentType.Ind].ptr))).GetComponent(entityID);
}

pub fn CreateEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(!self._EntityComponentArrays.hasSparse(entityID));
    const dense_ind = self._EntityComponentArrays.add(entityID);
    self._EntityComponentArrays.getValueByDense(dense_ind).* = StaticSkipField(ComponentsList.len).Init(.AllSkip);
}
pub fn DestroyEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(self._EntityComponentArrays.hasSparse(entityID));

    const entity_skipfield = self._EntityComponentArrays.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        try self._ComponentsArrays.items[i].RemoveComponent(entityID);
        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
    _ = self._EntityComponentArrays.remove(entityID);
}
