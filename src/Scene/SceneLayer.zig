const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;
const SceneLayer = @This();
const Set = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

//.gscl
//.oscl

mUUID: u64,
mName: [24]u8,
mLayerType: LayerType,
mEntities: Set(u32),

pub fn Init(ECSAllocator: std.mem.Allocator, layer_type: LayerType) SceneLayer {
    return SceneLayer{
        .mUUID = GenUUID(),
        .mName = std.mem.zeroes([24]u8),
        .mLayerType = layer_type,
        .mEntities = Set(u32).init(ECSAllocator),
    };
}

pub fn Deinit(self: *SceneLayer) void {
    self.mEntities.deinit();
}
