const std = @import("std");
const ISystem = @import("SystemClass.zig").ISystem;
const SystemsList = @import("Systems.zig").SystemsList;
const BitFieldType = @import("ComponentManager.zig").BitFieldType;
const SparseSet = @import("../Vendor/zig-sparse-set/src/sparse_set.zig").SparseSet;
const SystemManager = @This();

mSystemsArray: std.ArrayList(ISystem) = undefined,
mEntityBitField: SparseSet(.{
    .SparseT = u32,
    .DenseT = u32,
    .ValueT = BitFieldType,
    .value_layout = .InternalArrayOfStructs,
    .allow_resize = .ResizeAllowed,
}) = undefined,

pub fn Init(ECSAllocator: std.mem.Allocator) !SystemManager {
    var new_system_manager = SystemManager{
        .mSystemsArray = std.ArrayList(ISystem).init(ECSAllocator),
        .mEntityBitField = try SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = BitFieldType,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }).init(ECSAllocator, 20, 10),
    };

    inline for (SystemsList) |system_type| {
        const new_system = try ECSAllocator.create(system_type);

        new_system.* = system_type.Init();

        const i_system = ISystem.Init(new_system, ECSAllocator, &system_type.Types);

        try new_system_manager.mSystemsArray.append(i_system);
    }
    return new_system_manager;
}

pub fn Deinit(self: *SystemManager, ECSAllocator: std.mem.Allocator) void {
    for (self.mSystemsArray.items) |*system| {
        system.Deinit(ECSAllocator);
    }

    self.mSystemsArray.deinit();
    self.mEntityBitField.deinit();
}

pub fn AddComponent(self: *SystemManager, comptime component_type: type, entityID: u32) !void {
    const entity_bitfield = self.mEntityBitField.getValueBySparse(entityID);
    entity_bitfield.* |= 1 << component_type.Ind;
    for (self.mSystemsArray.items) |*system| {
        if (@as(BitFieldType, 1) << component_type.Ind & system.mBitField > 0 and entity_bitfield.* & system.mBitField > 0) {
            _ = try system.mEntities.add(entityID);
        }
    }
}

pub fn RemoveComponent(self: *SystemManager, comptime component_type: type, entityID: u32) void {
    const entity_bitfield = self.mEntityBitField.getValueBySparse(entityID);
    for (self.mSystemsArray.items) |*system| {
        if (@as(BitFieldType, 1) << component_type.Ind & system.mBitField > 0 and entity_bitfield.* & system.mBitField > 0) {
            _ = system.mEntities.remove(entityID);
        }
    }
    entity_bitfield.* &= ~(@as(BitFieldType, 1) << component_type.Ind);
}

pub fn DuplicateEntity(self: *SystemManager, original_entity_id: u32, new_entity_id: u32) void {
    self.mEntityBitField.getValueBySparse(new_entity_id).* = self.mEntityBitField.getValueBySparse(original_entity_id).*;
}

pub fn CreateEntity(self: *SystemManager, entityID: u32) void {
    const dense_ind = self.mEntityBitField.add(entityID);
    self.mEntityBitField.getValueByDense(dense_ind).* = 0;
}

pub fn DestroyEntity(self: *SystemManager, entityID: u32) void {
    //remove from each system that matches the entitys bitfield
    const entity_bitfield = self.mEntityBitField.getValueBySparse(entityID).*;
    for (self.mSystemsArray.items) |*system| {
        if (entity_bitfield & system.mBitField > 0) {
            _ = system.mEntities.remove(entityID);
        }
    }
    self.mEntityBitField.remove(entityID);
}

pub fn SystemOnUpdate(self: *SystemManager, comptime system: type) !void {
    try self.mSystemsArray.items[system.Ind].OnUpdate(self.mSystemsArray.items[system.Ind].mEntities);
}
