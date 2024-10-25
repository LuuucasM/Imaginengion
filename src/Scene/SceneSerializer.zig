const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("../ECS/Components/SceneIDComponent.zig").ELayerType;
const EComponents = @import("../ECS/Components.zig").EComponents;
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
pub fn DeSerializeText(scene_layer: *SceneLayer) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try std.fs.openFileAbsolute(scene_layer.mPath.items, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, @intCast(file_size));
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    var scanner = std.json.Scanner.initCompleteInput(allocator, buffer);
    defer scanner.deinit();

    while (true) {
        const token = try scanner.next();
        switch (token) {
            .string => {
                const str = token.string;

                if (std.mem.eql(u8, str, "UUID") == true) {
                    const uuid_token = try scanner.next();
                    const uuid = try std.fmt.parseUnsigned(u128, uuid_token.number, 10);
                    scene_layer.mUUID = uuid;
                } else if (std.mem.eql(u8, str, "LayerType") == true) {
                    const layer_type_token = try scanner.next();
                    const layer_type = std.meta.stringToEnum(LayerType, layer_type_token.string).?;
                    scene_layer.mLayerType = layer_type;
                } else if (std.mem.eql(u8, str, "Entity") == true) {
                    const new_entity = try scene_layer.CreateNewEntity();
                    _ = try scanner.next(); //this is because the next scanner object will be beginObject token, and then after that we will get the object fields + data
                    while (true) {
                        const component_token = try scanner.next();
                        switch (component_token) {
                            .string => {
                                const ecomponent_type = std.meta.stringToEnum(EComponents, component_token.string).?;
                                const component_data_token = try scanner.next();
                                const component_string = component_data_token.string;
                                try new_entity.DeStringify(ecomponent_type, component_string);
                            },
                            .object_end => break,
                            else => continue,
                        }
                    }
                    _ = try scene_layer.mEntityIDs.add(new_entity.mEntityID);
                }
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
