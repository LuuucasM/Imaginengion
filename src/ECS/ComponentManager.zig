const std = @import("std");
const IComponentArray = @import("ComponentArray.zig").IComponentArray;
const ComponentArray = @import("ComponentArray.zig").ComponentArray;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ArraySet = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;
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
mECSAllocator: std.mem.Allocator,

pub fn Init(ECSAllocator: std.mem.Allocator, comptime components_list: []const type) !ComponentManager {
    var new_component_manager = ComponentManager{
        .mComponentsArrays = std.ArrayList(IComponentArray).init(ECSAllocator),
        .mEntitySkipField = try SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = StaticSkipField(32 + 1), //TODO: 32 is arbitrary
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }).init(ECSAllocator, 20, 10),
        .mECSAllocator = ECSAllocator,
    };

    inline for (components_list) |component_type| {
        const component_array = try ECSAllocator.create(ComponentArray(component_type));

        component_array.* = try ComponentArray(component_type).Init(ECSAllocator);

        const i_component_array = IComponentArray.Init(component_array);

        try new_component_manager.mComponentsArrays.append(i_component_array);
    }

    return new_component_manager;
}

pub fn Deinit(self: *ComponentManager) void {
    //delete component arrays
    for (self.mComponentsArrays.items) |component_array| {
        component_array.Deinit(self.mECSAllocator);
    }

    self.mComponentsArrays.deinit();
    self.mEntitySkipField.deinit();
}

pub fn CreateEntity(self: *ComponentManager, entityID: u32) !void {
    std.debug.assert(!self.mEntitySkipField.hasSparse(entityID));
    const dense_ind = self.mEntitySkipField.add(entityID);
    self.mEntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(32 + 1).Init(.AllSkip); //TODO: 32 is arbitrary
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
    std.debug.assert(self.mEntitySkipField.hasSparse(original_entity_id));
    std.debug.assert(self.mEntitySkipField.hasSparse(new_entity_id));

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

pub fn AddComponent(self: *ComponentManager, comptime component_type: type, entityID: u32, component: ?component_type) !*component_type {
    std.debug.assert(@hasDecl(component_type, "Ind"));
    std.debug.assert(!self.HasComponent(component_type, entityID));
    std.debug.assert(self.mEntitySkipField.hasSparse(entityID));
    std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);

    self.mEntitySkipField.getValueBySparse(entityID).ChangeToUnskipped(component_type.Ind);

    return try @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr))).AddComponent(entityID, component);
}

pub fn RemoveComponent(self: *ComponentManager, comptime component_type: type, entityID: u32) !void {
    std.debug.assert(@hasDecl(component_type, "Ind"));
    std.debug.assert(self.mEntitySkipField.hasSparse(entityID));
    std.debug.assert(self.HasComponent(component_type, entityID));
    std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);

    self.mEntitySkipField.getValueBySparse(entityID).ChangeToSkipped(component_type.Ind);

    return try self.mComponentsArrays.items[component_type.Ind].RemoveComponent(entityID);
}

pub fn HasComponent(self: ComponentManager, comptime component_type: type, entityID: u32) bool {
    std.debug.assert(@hasDecl(component_type, "Ind"));
    std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
    return @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr))).HasComponent(entityID);
}

pub fn GetComponent(self: ComponentManager, comptime component_type: type, entityID: u32) *component_type {
    std.debug.assert(@hasDecl(component_type, "Ind"));
    std.debug.assert(self.HasComponent(component_type, entityID));
    std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
    return @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr))).GetComponent(entityID);
}

pub fn GetGroup(self: ComponentManager, comptime ComponentTypes: []const type, allocator: std.mem.Allocator) !ArraySet(u32) {
    std.debug.assert(ComponentTypes.len > 0);
    if (ComponentTypes.len == 1) {
        std.debug.assert(@hasDecl(ComponentTypes[0], "Ind"));
        std.debug.assert(ComponentTypes[0].Ind < self.mComponentsArrays.items.len);
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
        std.debug.assert(@hasDecl(component_type, "Ind"));
        std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
        const component_array = @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr)));
        const num_dense = component_array.NumOfComponents();
        if (num_dense < smallest_len) {
            smallest_ind = i;
            smallest_len = num_dense;
        }
    }

    var group = try ArraySet(u32).initCapacity(allocator, smallest_len);
    std.debug.assert(@hasDecl(ComponentTypes[smallest_ind], "Ind"));
    std.debug.assert(ComponentTypes[smallest_ind].Ind < self.mComponentsArrays.items.len);
    const smallest_component_array = @as(*ComponentArray(ComponentTypes[smallest_ind]), @alignCast(@ptrCast(self._ComponentsArrays.items[ComponentTypes[smallest_ind].Ind].ptr)));
    outer: for (smallest_component_array.mComponents.dense_to_sparse[0..smallest_len]) |value| {
        inline for (ComponentTypes, 0..) |component_type, i| {
            if (i == smallest_ind) continue;
            std.debug.assert(@hasDecl(component_type, "Ind"));
            std.debug.assert(component_type.Ind < self.mComponentsArrays.items.len);
            const component_array = @as(*ComponentArray(component_type), @alignCast(@ptrCast(self.mComponentsArrays.items[component_type.Ind].ptr)));
            if (!component_array.mComponents.hasSparse(value)) continue :outer;
        }
        _ = try group.add(value);
    }

    return group;
}
