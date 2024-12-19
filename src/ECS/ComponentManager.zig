const std = @import("std");
const IComponentArray = @import("ComponentArray.zig").IComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const Components = @import("Components.zig");
const EComponents = Components.EComponents;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;

const ComponentManager = @This();

pub const BitFieldType: type = std.meta.Int(.unsigned, 32); //32 is abitrary

_ComponentsArrays: std.ArrayList(IComponentArray),
_EntitySkipField: SparseSet(.{
    .SparseT = u32,
    .DenseT = u32,
    .ValueT = StaticSkipField(32 + 1), //32 is abritrary number
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
}),

pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_list: []const type) !ComponentManager {
    var new_component_manager = ComponentManager{
        ._ComponentsArrays = std.ArrayList(IComponentArray).init(ECSAllocator),
        ._EntitySkipField = try SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = StaticSkipField(32 + 1), //32 is abitrary number
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }).init(ECSAllocator, 20, 10),
    };

    //init component arrays
    inline for (components_list) |component_type| {
        const component_array = try ECSAllocator.create(ComponentArray(component_type));
        component_array.* = try ComponentArray(component_type).Init(ECSAllocator);

        const i_component_array = IComponentArray.Init(component_array);

        try new_component_manager._ComponentsArrays.append(i_component_array);
    }

    return new_component_manager;
}

pub fn Deinit(self: *ComponentManager, ECSAllocator: std.mem.Allocator) void {
    //delete component arrays
    for (self._ComponentsArrays.items) |component_array| {
        component_array.Deinit(ECSAllocator);
    }

    self._ComponentsArrays.deinit();
    self._EntitySkipField.deinit();
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

pub fn GetOrAddComponent(self: ComponentManager, comptime ComponentType: type, entityID: u32) *ComponentType {
    if (self.HasComponent(ComponentType, entityID) == true) {} else {}
    return self.GetComponent(ComponentType, entityID);
}

pub fn Stringify(self: ComponentManager, write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), entityID: u32) !void {
    std.debug.assert(self._EntitySkipField.hasSparse(entityID));
    const entity_skipfield = self._EntitySkipField.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        try self._ComponentsArrays.items[i].Stringify(write_stream, entityID);

        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
}

pub fn DeStringify(self: *ComponentManager, components_index: usize, component_string: []const u8, entityID: u32) !void {
    std.debug.assert(components_index < self._ComponentsArrays.items.len);
    std.debug.assert(self._EntitySkipField.hasSparse(entityID));

    try self._ComponentsArrays.items[components_index].DeStringify(component_string, entityID);
}

pub fn CreateEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(!self._EntitySkipField.hasSparse(entityID));
    const dense_ind = self._EntitySkipField.add(entityID);
    self._EntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(32 + 1).Init(.AllSkip); //32 is arbitrary
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

pub fn EntityImguiRender(self: ComponentManager, entityID: u32) void {
    std.debug.assert(self._EntitySkipField.hasSparse(entityID));
    const entity_skipfield = self._EntitySkipField.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        self._ComponentsArrays.items[i].ImguiRender(entityID);

        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
}
