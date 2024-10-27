const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = SceneLayer.LayerType;
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

    var write_stream = std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }).init(undefined, out.writer(), .{ .whitespace = .indent_2 });
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
        try entity.Stringify(&write_stream);
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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const token_allocator = arena.allocator();
    defer arena.deinit();

    while (true) {
        const token = try scanner.nextAlloc(token_allocator, .alloc_if_needed);
        const value = switch (token) {
            .string => |value| value,
            .number => |value| value,
            //.allocated_string => |value| value,
            //.allocated_number => |value| value,
            .end_of_document => break,
            else => "",
        };
        if (value.len > 0) {
            if (std.mem.eql(u8, value, "UUID") == true) {
                const uuid_token = try scanner.nextAlloc(token_allocator, .alloc_if_needed);
                const uuid_value = switch (uuid_token) {
                    .number => |uuid_value| uuid_value,
                    .allocated_number => |uuid_value| uuid_value,
                    else => @panic("should be a number!\n"),
                };
                scene_layer.mUUID = try std.fmt.parseUnsigned(u128, uuid_value, 10);
            } else if (std.mem.eql(u8, value, "LayerType") == true) {
                const layer_type_token = try scanner.nextAlloc(token_allocator, .alloc_if_needed);
                const layer_type_value = switch (layer_type_token) {
                    .string => |layer_type_value| layer_type_value,
                    .allocated_string => |layer_type_value| layer_type_value,
                    else => @panic("Should be a string!\n"),
                };
                scene_layer.mLayerType = std.meta.stringToEnum(LayerType, layer_type_value).?;
            } else if (std.mem.eql(u8, value, "Entity") == true) {
                const new_entity = try scene_layer.CreateBlankEntity();
                _ = try scanner.next(); //for the start of the new object
                while (true) {
                    const component_type_token = try scanner.nextAlloc(token_allocator, .alloc_if_needed);
                    const component_type_string = switch (component_type_token) {
                        .string => |component_type| component_type,
                        .allocated_string => |component_type| component_type,
                        .object_end => break,
                        else => @panic("should be a string!\n"),
                    };
                    const component_type = std.meta.stringToEnum(EComponents, component_type_string).?;

                    const component_data_token = try scanner.nextAlloc(token_allocator, .alloc_if_needed);
                    const component_data_string = switch (component_data_token) {
                        .string => |component_data| component_data,
                        .allocated_string => |component_data| component_data,
                        else => @panic("should be a string!!\n"),
                    };

                    try new_entity.DeStringify(@intFromEnum(component_type), component_data_string);
                }
            }
        }
        _ = arena.reset(.retain_capacity);
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
