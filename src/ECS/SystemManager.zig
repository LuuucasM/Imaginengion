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
mECSAllocator: std.mem.Allocator,

pub fn Init(ECSAllocator: std.mem.Allocator, system_types: []const type) !SystemManager {
    var new_system_manager = SystemManager{
        .mSystemsArray = std.ArrayList(ISystem).init(ECSAllocator),
        .mEntityBitField = try SparseSet(.{
            .SparseT = u32,
            .DenseT = u32,
            .ValueT = BitFieldType,
            .value_layout = .InternalArrayOfStructs,
            .allow_resize = .ResizeAllowed,
        }).init(ECSAllocator, 20, 10),
        .mECSAllocator = ECSAllocator,
    };

    inline for (system_types) |system_type| {
        const new_system = try ECSAllocator.create(system_type);

        new_system.* = system_type.Init();

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
    self.mEntityBitField.deinit();
}

pub fn AddComponent(self: *SystemManager, comptime component_type: type, entityID: u32) !void {
    _ = self;
    _ = component_type;
    _ = entityID;
}

pub fn RemoveComponent(self: *SystemManager, comptime component_type: type, entityID: u32) void {
    _ = self;
    _ = component_type;
    _ = entityID;
}

pub fn DuplicateEntity(self: *SystemManager, original_entity_id: u32, new_entity_id: u32) void {
    _ = self;
    _ = original_entity_id;
    _ = new_entity_id;
}

pub fn CreateEntity(self: *SystemManager, entityID: u32) void {
    _ = self;
    _ = entityID;
}

pub fn DestroyEntity(self: *SystemManager, entityID: u32) void {
    _ = self;
    _ = entityID;
}

pub fn SystemOnUpdate(self: *SystemManager, comptime system: type) !void {
    _ = self;
    _ = system;
}
