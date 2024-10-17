const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;
const SceneLayerEditor = @This();
const Set = @import("../Vendor/ziglang-set/src/array_hash_set/managed.zig").ArraySetManaged;

//.gscl
//.oscl

mUUID: u64,
mName: [24]u8,
mLayerType: LayerType,
mEntities: Set(u32),
