const LayerType = SceneIDComponent.ELayerType;
const SceneLayerEditor = @This();
const Set = @import("../Vendor/ziglang-set/src/array_has_set/")

//.gscl
//.oscl

mUUID: u64,
mName: [24]u8,
mLayerType: LayerType,
mEntities: Set(u32),