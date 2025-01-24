const std = @import("std");
const ISystem = @import("ISystem.zig").ISystem;
const SystemsList = @import("../GameObjects/Systems.zig").SystemsList;
const BitFieldType = @import("ComponentManager.zig").BitFieldType;
const StaticSkipField = @import("../Core/SkipField.zig").StaticSkipField;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const ComponentManager = @import("ComponentManager.zig");
const SystemManager = @This();

mSystemsArray: std.ArrayList(ISystem) = undefined,
mEntitySkipField: SparseSet(.{
    .SparseT = u32,
    .DenseT = u32,
    .ValueT = StaticSkipField(32 + 1),
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
}) = undefined,
mECSAllocator: std.mem.Allocator,

pub fn Init(ECSAllocator: std.mem.Allocator, system_types: []const type) !SystemManager {
    var new_system_manager = SystemManager{
        .mSystemsArray = std.ArrayList(ISystem).init(ECSAllocator),
        .mEntitySkipField = try SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = StaticSkipField(32 + 1),
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }).init(ECSAllocator, 20, 10),
        .mECSAllocator = ECSAllocator,
    };

    inline for (system_types) |system_type| {
        const new_system = try ECSAllocator.create(system_type);

        new_system.* = system_type.Init(ECSAllocator);

        const i_system = ISystem.Init(new_system);

        try new_system_manager.mSystemsArray.append(i_system);
    }
    return new_system_manager;
}

pub fn Deinit(self: *SystemManager) void {
    for (self.mSystemsArray) |system_array| {
        system_array.Deinit(self.mECSAllocator);
    }
    self.mSystemsArray.deinit();
    self.mEntitySkipField.deinit();
}

pub fn CreateEntity(self: *SystemManager, entityID: u32) void {
    std.debug.assert(!self.mEntitySkipField.hasSparse(entityID));
    const dense_ind = self.mEntitySkipField.add(entityID);
    self.mEntitySkipField.getValueByDense(dense_ind).* = StaticSkipField(32 + 1).Init(.AllSkip);
}

pub fn DestroyEntity(self: *SystemManager, entityID: u32) void {
    std.debug.assert(self.mEntitySkipField.hasSparse(entityID));

    const entity_skipfield = self.mEntitySkipField.getValueBySparse(entityID);

    var i: usize = entity_skipfield.mSkipField[0];
    while (i < entity_skipfield.mSkipField.len) {
        self.mSystemsArray.items[i].RemoveEntity(entityID);
        i += 1;
        i += entity_skipfield.mSkipField[i];
    }
    _ = self.mEntitySkipField.remove(entityID);
}

pub fn DuplicateEntity(self: *SystemManager, original_entity_id: u32, new_entity_id: u32) void {
    std.debug.assert(self.mEntitySkipField.hasSparse(original_entity_id));
    std.debug.assert(self.mEntitySkipField.hasSparse(new_entity_id));

    const original_skipfield = self.mEntitySkipField.getValueBySparse(original_entity_id);
    const new_skipfield = self.mEntitySkipField.getValueBySparse(new_entity_id);
    @memcpy(&new_skipfield.mSkipField, &original_skipfield.mSkipField);

    var i: usize = original_skipfield.mSkipField[0];
    while (i < original_skipfield.mSkipField.len) {
        self.mSystemsArray.items[i].AddEntity(new_entity_id);
        i += 1;
        i += original_skipfield.mSkipField[i];
    }
}

pub fn AddComponent(self: *SystemManager, component_skipfield: StaticSkipField(32 + 1), entity_id: u32) !void {
    for (self.mSystemsArray.items, 0..) |*array, system_index| {
        const component_field = array.GetComponentField();
        var compatible = true;

        for (component_field.mSkipField, 0..) |val, j| {
            if (val == 0 and component_skipfield.mSkipField[j] != 0) {
                compatible = false;
                break;
            }
        }
        if (compatible == true) {
            self.mEntitySkipField.getValueBySparse(entity_id).ChangeToUnskipped(@intCast(system_index));
            try array.AddEntity(entity_id);
        }
    }
}

pub fn RemoveComponent(self: *SystemManager, component_skipfield: StaticSkipField(32 + 1), entity_id: u32) void {
    for (self.mSystemsArray.items, 0..) |*array, system_index| {
        const component_field = array.GetComponentField();
        var compatible = true;

        for (component_field.mSkipField, 0..) |val, j| {
            if (val == 0 and component_skipfield.mSkipField[j] != 0) {
                compatible = false;
                break;
            }
        }

        if (!compatible) {
            self.mEntitySkipField.getValueBySparse(entity_id).ChangeToSkipped(@intCast(system_index));
            array.RemoveEntity(entity_id);
        }
    }
}

pub fn SystemOnUpdate(self: *SystemManager, comptime system: type, component_manager: ComponentManager) !void {
    try self.mSystemsArray.items[system.Ind].OnUpdate(component_manager);
}
