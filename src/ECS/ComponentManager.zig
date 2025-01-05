const std = @import("std");
const IComponentArray = @import("ComponentArray.zig").IComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const Components = @import("Components.zig");
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
const Entity = @import("Entity.zig");
const ComponentManager = @This();

pub const BitFieldType: type = std.meta.Int(.unsigned, 32); //32 is abitrary

mComponentsArrays: std.ArrayList(IComponentArray),
mEntitySkipField: SparseSet(.{
    .SparseT = u32,
    .DenseT = u32,
    .ValueT = StaticSkipField(32 + 1), //32 is abritrary number
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
}),

pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_list: []const type) !ComponentManager {
    var new_component_manager = ComponentManager{
        .mComponentsArrays = std.ArrayList(IComponentArray).init(ECSAllocator),
        .mEntitySkipField = try SparseSet(.{
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

        try new_component_manager.mComponentsArrays.append(i_component_array);
    }

    return new_component_manager;
}

pub fn Deinit(self: *ComponentManager, ECSAllocator: std.mem.Allocator) void {
    //delete component arrays
    for (self.mComponentsArrays.items) |component_array| {
        component_array.Deinit(ECSAllocator);
    }

    self.mComponentsArrays.deinit();
    self.mEntitySkipField.deinit();
}

pub fn AddComponent(self: *ComponentManager, comptime ComponentType: type, entityID: u32, component: ComponentType) !*ComponentType {
    std.debug.assert(!self.HasComponent(ComponentType, entityID)); //TODO: remove asserts and replace it with a better way to check input

    self.mEntitySkipField.getValueBySparse(entityID).ChangeToUnskipped(ComponentType.Ind);

    return try @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self.mComponentsArrays.items[ComponentType.Ind].ptr))).AddComponent(entityID, component);
}

pub fn RemoveComponent(self: *ComponentManager, comptime ComponentType: type, entityID: u32) !void {
    std.debug.assert(self.HasComponent(ComponentType, entityID));

    self.mEntitySkipField.getValueBySparse(entityID).ChangeToSkipped(ComponentType.Ind);

    return try self.mComponentsArrays.items[ComponentType.Ind].RemoveComponent(entityID);
}

pub fn HasComponent(self: ComponentManager, comptime ComponentType: type, entityID: u32) bool {
    return @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self.mComponentsArrays.items[ComponentType.Ind].ptr))).HasComponent(entityID);
}

pub fn GetComponent(self: ComponentManager, comptime ComponentType: type, entityID: u32) *ComponentType {
    std.debug.assert(self.HasComponent(ComponentType, entityID));
    return @as(*ComponentArray(ComponentType), @alignCast(@ptrCast(self.mComponentsArrays.items[ComponentType.Ind].ptr))).GetComponent(entityID);
}

pub fn GetGroup(self: ComponentManager, comptime ComponentTypes: []const type, allocator: std.mem.Allocator) !ArraySet(u32) {
    std.debug.assert(ComponentTypes.len > 0);
    if (ComponentTypes.len == 1) {
        const component_array = @as(*ComponentArray(ComponentTypes[0]), @alignCast(@ptrCast(self.mComponentsArrays.items[ComponentTypes[0].Ind].ptr)));
        var group = try ArraySet(u32).initCapacity(allocator, component_array.NumOfComponents());
        const num_dense = component_array.NumOfComponents();
        for (component_array.mComponents.dense_to_sparse[0..num_dense]) |value| {
            _ = try group.add(value);
        }
        return group;
    }

    var smallest_ind: usize = 0;
    var smallest_len: usize = std.math.maxInt(usize);
    inline for (ComponentTypes, 0..) |component_type, i| {
        const component_array = @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr)));
        const num_dense = component_array.NumOfComponents();
        if (num_dense < smallest_len) {
            smallest_ind = i;
            smallest_len = num_dense;
        }
    }

    var group = try ArraySet(u32).initCapacity(allocator, smallest_len);

    const smallest_component_array = @as(*ComponentArray(ComponentTypes[smallest_ind]), @alignCast(@ptrCast(self._ComponentsArrays.items[ComponentTypes[smallest_ind].Ind].ptr)));
    outer: for (smallest_component_array.mComponents.dense_to_sparse[0..smallest_len]) |value| {
        inline for (ComponentTypes, 0..) |component_type, i| {
            if (i == smallest_ind) continue;
            const component_array = @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr)));
            if (!component_array.mComponents.hasSparse(value)) continue :outer;
        }
        _ = try group.add(value);
    }

    return group;
}

pub fn Stringify(self: ComponentManager, write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), entityID: u32) !void {
    std.debug.assert(self.mEntitySkipField.hasSparse(entityID));
    const entity_skipfield = self.mEntitySkipField.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        try self.mComponentsArrays.items[i].Stringify(write_stream, entityID);

        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
}

pub fn DeStringify(self: *ComponentManager, components_index: usize, component_string: []const u8, entityID: u32) !void {
    std.debug.assert(components_index < self.mComponentsArrays.items.len);
    std.debug.assert(self.mEntitySkipField.hasSparse(entityID));
    const component_ind = try self.mComponentsArrays.items[components_index].DeStringify(component_string, entityID);
    self.mEntitySkipField.getValueBySparse(entityID).ChangeToUnskipped(@intCast(component_ind));
}

pub fn CreateEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(!self.mEntitySkipField.hasSparse(entityID));
    const dense_ind = self.mEntitySkipField.add(entityID);
    self.mEntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(32 + 1).Init(.AllSkip); //32 is arbitrary
}
pub fn DestroyEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(self.mEntitySkipField.hasSparse(entityID));

    const entity_skipfield = self.mEntitySkipField.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        try self.mComponentsArrays.items[i].RemoveComponent(entityID);
        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
    _ = self.mEntitySkipField.remove(entityID);
}

pub fn DuplicateEntity(self: *ComponentManager, original_entity_id: u32, new_entity_id: u32) void {
    const original_skipfield = self.mEntitySkipField.getValueBySparse(original_entity_id);
    const new_skipfield = self.mEntitySkipField.getValueBySparse(new_entity_id);
    @memcpy(&new_skipfield.mSkipField, &original_skipfield.mSkipField);

    var i: usize = original_skipfield.mSkipField[0];
    while (i < original_skipfield.mSkipField.len) {
        self.mComponentsArrays.items[i].DuplicateEntity(original_entity_id, new_entity_id);
        i += 1;
        i += original_skipfield.mSkipField[i];
    }
}

pub fn EntityImguiRender(self: ComponentManager, entity: Entity) !void {
    std.debug.assert(self.mEntitySkipField.hasSparse(entity.mEntityID));
    const entity_skipfield = self.mEntitySkipField.getValueBySparse(entity.mEntityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        try self.mComponentsArrays.items[i].ImguiRender(entity);
        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
}
