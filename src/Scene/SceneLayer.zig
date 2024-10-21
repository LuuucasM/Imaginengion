const std = @import("std");
const GenUUID = @import("../Core/UUID.zig").GenUUID;
const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;
const SceneLayer = @This();
const Set = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

//.gscl
//.oscl

mName: std.ArrayList(u8),
mUUID: u128,
mPath: std.ArrayList(u8),
mLayerType: LayerType,
mInternalID: u8,
mEntities: Set(u32),

pub fn Init(ECSAllocator: std.mem.Allocator, layer_type: LayerType, internal_id: u8) !SceneLayer {
    return SceneLayer{
        .mUUID = try GenUUID(),
        .mName = std.ArrayList(u8).init(ECSAllocator),
        .mPath = std.ArrayList(u8).init(ECSAllocator),
        .mLayerType = layer_type,
        .mInternalID = internal_id,
        .mEntities = Set(u32).init(ECSAllocator),
    };
}

pub fn Deinit(self: *SceneLayer) void {
    self.mName.deinit();
    self.mPath.deinit();
    self.mEntities.deinit();
}
