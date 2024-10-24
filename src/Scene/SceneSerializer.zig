const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const Entity = @import("../ECS/Entity.zig");
const Components = @import("../ECS/Components.zig");
const SceneManager = @import("SceneManager.zig");

pub fn SerializeText(scene_layer: *SceneLayer) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var write_stream = std.json.writeStream(out.writer(), .{ .whitespace = .indent_2 });
    defer write_stream.deinit();

    try write_stream.beginObject();

    try write_stream.objectField("UUID");
    try write_stream.write(scene_layer.mUUID);

    try write_stream.objectField("LayerType");
    try write_stream.write(scene_layer.mLayerType);

    var iter = scene_layer.mEntityIDs.iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        const entity = Entity{ .mEntityID = entity_id, .mSceneLayerRef = scene_layer };

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
pub fn DeserializeText(scene_layer: *SceneLayer) SceneLayer {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try std.fs.openFileAbsolute(scene_layer.mPath);
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, @intCast(file_size));
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    var scanner = std.json.Scanner.initCompleteInput(allocator, buffer);
    defer scanner.deinit();

    //var entity: Entity = Entity{ .mEntityID = Entity.NullEntity, .mSceneLayerRef = scene_layer };

    while (true) {
        const token = try scanner.next();
        switch (token) {
            .string => {
                //check if token.string == UUID, if so scanner.next and set token.number to the uuid if scene_panel
                //check if token.string == LayerType, if so scanner.next and set scene_panel.mPanelType according to what token.string is
                //check if token.string == Entity, create a new entity id from the ECS manager, then set entity variable using entityid and scene_layer
                //while true, scanner.next and manually write out a check for each component type and if it is that type then add it to the entity
                //on object_end add the entity to the scene_panel.entityIDs and set entity variable back to the null entity then break
                //else ignore
            },
            .end_of_document => break,
            else => continue,
        }
    }
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
