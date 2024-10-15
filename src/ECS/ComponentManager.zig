const std = @import("std");
const IComponentArray = @import("ComponentArray.zig").IComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const Components = @import("Components.zig");
const ComponentsList = Components.ComponentsList;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

const ComponentManager = @This();

pub const BitFieldType: type = std.meta.Int(.unsigned, ComponentsList.len);

const ComponentData = struct {
    mBitField: BitFieldType,
    mSkipField: StaticSkipField(ComponentsList.len),
};

_ComponentsArrays: std.ArrayList(IComponentArray),
_EntitySkipField: SparseSet(.{
    .SparseT = u32,
    .DenseT = u32,
    .ValueT = StaticSkipField(ComponentsList.len),
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
}),
var ComponentGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},

pub fn Init() !ComponentManager {
    const new_component_manager = ComponentManager{
        ._ComponentsArrays = std.ArrayList(IComponentArray).init(ComponentGPA.allocator()),
        ._EntitySkipField = try SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = StaticSkipField(ComponentsList.len),
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }).init(ComponentGPA.allocator(), 20, 10),
    };

    //init component arrays
    inline for (ComponentsList) |component_type| {
        const component_array = ComponentGPA.allocator().create(ComponentArray(component_type));
        component_array.* = try ComponentArray(component_type).Init(ComponentGPA.allocator());

        const i_component_array = IComponentArray.Init(component_array);

        try new_component_manager._ComponentsArrays.append(i_component_array);
    }

    return new_component_manager;
}

pub fn Deinit(self: *ComponentManager) void {
    //delete component arrays
    for (self._ComponentsArrays.items) |component_array| {
        component_array.Deinit(self._ComponentGPA.allocator());
    }

    self._ComponentsArrays.deinit();
    self._EntitySkipField.deinit();
    _ = self._ComponentGPA.deinit();
}

pub fn AddComponent(self: *ComponentManager, comptime ComponentType: type, entityID: u32, component: ComponentType) !*ComponentType {
    std.debug.assert(!self.HasComponent(ComponentType, entityID)); //TODO: remove asserts and replace it with a better way to check input

    self._EntitySkipField.getValueBySparse(entityID).ChangeToUnskipped(ComponentType.Ind);

    return try @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self._ComponentsArrays.items[ComponentType.Ind].ptr))).AddComponent(entityID, component);
}

pub fn RemoveComponent(self: *ComponentManager, comptime ComponentType: type, entityID: u32) !void {
    std.debug.assert(self.HasComponent(ComponentType, entityID));

    self._EntitySkipField.getValueBySparse(entityID).ChangeToSkipped(ComponentType.Ind);

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
    std.debug.assert(!self._EntitySkipField.hasSparse(entityID));
    const dense_ind = self._EntitySkipField.add(entityID);
    self._EntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(ComponentsList.len).Init(.AllSkip);
}
pub fn DestroyEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(self._EntitySkipField.hasSparse(entityID));

    const entity_skipfield = self._EntitySkipField.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        try self._ComponentsArrays.items[i].RemoveComponent(entityID);
        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
    _ = self._EntitySkipField.remove(entityID);
}

pub fn DuplicateEntity(self: *ComponentManager, original_entity_id: u32, new_entity_id: u32) void {
    const original_skipfield = self._EntitySkipField.getValueBySparse(original_entity_id);
    const new_skipfield = self._EntitySkipField.getValueBySparse(new_entity_id);
    @memcpy(&new_skipfield.mSkipField, &original_skipfield.mSkipField);

    var i: usize = original_skipfield.mSkipField[0];
    while (i < original_skipfield.mSkipField.len) {
        self._ComponentsArrays.items[i].DuplicateEntity(original_entity_id, new_entity_id);
        i += 1;
        i += original_skipfield.mSkipField[i];
    }
}
