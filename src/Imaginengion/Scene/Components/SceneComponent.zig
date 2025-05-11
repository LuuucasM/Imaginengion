const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const EntityType = @import("../SceneManager.zig").EntityType;
const ECSManagerScenes = @import("../SceneManager.zig").ECSManagerScenes;
const FrameBuffer = @import("../../FrameBuffers/FrameBuffer.zig");
const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

mPath: std.ArrayList(u8),
mEntityList: std.ArrayList(EntityType),
mEntitySet: std.AutoHashMap(EntityType, usize),
mLayerType: LayerType,
mFrameBuffer: FrameBuffer,
mECSManagerRef: *ECSManagerScenes,

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SceneComponent) {
            break :blk i;
        }
    }
};
