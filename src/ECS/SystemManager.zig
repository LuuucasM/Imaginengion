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
mSystemsGPA: std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},

pub fn Init(self: *SystemManager) !void {
    self.mSystemsArray = std.ArrayList(ISystem).init(self.mSystemsGPA.allocator());
    self.mEntityBitField = try SparseSet(.{
        .SparseT = u32,
        .DenseT = u32,
        .ValueT = BitFieldType,
        .value_layout = .InternalArrayOfStructs,
        .allow_resize = .ResizeAllowed,
    }).init(self.mSystemsGPA.allocator(), 20, 10);

    inline for (SystemsList) |system_type| {
        const new_system = try self.mSystemsGPA.allocator().create(system_type);

        new_system.* = system_type.Init();

        const i_system = ISystem.Init(new_system, self.mSystemsGPA.allocator(), &system_type.Types);

        try self.mSystemsArray.append(i_system);
    }
}

pub fn Deinit(self: *SystemManager) void {
    for (self.mSystemsArray.items) |*system| {
        system.Deinit(self.mSystemsGPA.allocator());
    }

    self.mSystemsArray.deinit();
    self.mEntityBitField.deinit();
    _ = self.mSystemsGPA.deinit();
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
    try self.mSystemsArray.items[system.Ind].OnUpdate();
}
