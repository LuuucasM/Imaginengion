const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const Entity = @import("../ECS/Entity.zig");
const Components = @import("../ECS/Components.zig");
const SceneManager = @import("SceneManager.zig");

pub fn SerializeText(scene_layer: SceneLayer, scene_manager: *SceneManager) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var write_stream = std.json.writeStream(out.writer(), .{ .whitespace = .indent_2 });
    defer write_stream.deinit();

    try write_stream.beginObject();
    try write_stream.objectField("Name");
    try write_stream.write(scene_layer.mName.items);

    try write_stream.objectField("UUID");
    try write_stream.write(scene_layer.mUUID);

    try write_stream.objectField("LayerType");
    try write_stream.write(scene_layer.mLayerType);

    var iter = scene_layer.mEntities.iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        const entity = Entity{ .mEntityID = entity_id, .mECSManager = &scene_manager.mECSManager };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try entity.Stringify(&out);
        try write_stream.endObject();
    }
    try write_stream.endObject();
    const file = try std.fs.createFileAbsolute(
        scene_layer.mPath.items,
        .{ .read = false, .truncate = true },
    );
    defer file.close();
    try file.writeAll(out.items);
}
pub fn DeserializeText(path: []const u8, scene_manager: SceneManager, allocator: std.mem.Allocator) SceneLayer {
    _ = path;
    _ = scene_manager;
    _ = allocator;
}

pub fn SerializeBinary(scene_layer: SceneLayer, scene_manager: SceneManager) void {
    _ = scene_layer;
    _ = scene_manager;
}

pub fn DeserializeBinary(path: []const u8, scene_manager: SceneManager, allocator: std.mem.Allocator) SceneLayer {
    _ = path;
    _ = scene_manager;
    _ = allocator;
}
