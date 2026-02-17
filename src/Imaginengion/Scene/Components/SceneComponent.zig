const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const ECSManagerScenes = @import("../SceneManager.zig").ECSManagerScenes;
const AssetHandle = @import("../../Assets/AssetHandle.zig");

const EngineContext = @import("../../Core/EngineContext.zig");
const SceneComponent = @This();

pub const LayerType = enum(u1) {
    GameLayer = 0,
    OverlayLayer = 1,
};

pub const Name: []const u8 = "SceneComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SceneComponent) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mScenePath: std.ArrayList(u8) = .{}, //NOTE THIS IS THE RELATIVE PATH
mLayerType: LayerType = .GameLayer,

pub fn Deinit(self: *SceneComponent, engine_context: *EngineContext) !void {
    self.mScenePath.deinit(engine_context.EngineAllocator());
}

pub fn jsonStringify(self: *const SceneComponent, jw: anytype) !void {
    try jw.beginObject();

    try jw.objectField("LayerType");
    try jw.write(self.mLayerType);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!SceneComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: SceneComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        if (std.mem.eql(u8, field_name, "LayerType")) {
            result.mLayerType = try std.json.innerParse(LayerType, frame_allocator, reader, options);
        }
    }

    return result;
}
