const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = SceneLayer.LayerType;
const Entity = @import("../GameObjects/Entity.zig");

const Components = @import("../GameObjects/Components.zig");
const CameraComponent = Components.CameraComponent;
const CircleRenderComponent = Components.CircleRenderComponent;
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const SceneIDComponent = Components.SceneIDComponent;
const SpriteRenderComponent = Components.SpriteRenderComponent;
const TransformComponent = Components.TransformComponent;

const AssetManager = @import("../Assets/AssetManager.zig");
const SceneManager = @import("SceneManager.zig");

pub fn SerializeText(scene_layer: *SceneLayer) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var write_stream = std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }).init(undefined, out.writer(), .{ .whitespace = .indent_2 });
    defer write_stream.deinit();

    try write_stream.beginObject();

    try write_stream.objectField("UUID");
    try write_stream.write(scene_layer.mUUID);

    try write_stream.objectField("LayerType");
    try write_stream.write(scene_layer.mLayerType);

    var iter = scene_layer.mECSManagerRef.GetAllEntities().iterator();
    while (iter.next()) |entry| {
        const entity_id = entry.key_ptr.*;
        const entity = Entity{ .mEntityID = entity_id, .mSceneLayerRef = scene_layer };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try Stringify(&write_stream, entity);
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.openFileAbsolute(scene_layer.mPath.items, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, @intCast(file_size));
    defer allocator.free(buffer);

    _ = try file.readAll(buffer);

    var scanner = std.json.Scanner.initCompleteInput(allocator, buffer);
    defer scanner.deinit();

    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
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
                const uuid_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
                const uuid_value = switch (uuid_token) {
                    .number => |uuid_value| uuid_value,
                    .allocated_number => |uuid_value| uuid_value,
                    else => @panic("should be a number!\n"),
                };
                scene_layer.mUUID = try std.fmt.parseUnsigned(u128, uuid_value, 10);
            } else if (std.mem.eql(u8, value, "LayerType") == true) {
                const layer_type_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
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
                    const component_type_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
                    const component_type_string = switch (component_type_token) {
                        .string => |component_type| component_type,
                        .allocated_string => |component_type| component_type,
                        .object_end => break,
                        else => @panic("should be a string!\n"),
                    };

                    const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
                    const component_data_string = switch (component_data_token) {
                        .string => |component_data| component_data,
                        .allocated_string => |component_data| component_data,
                        else => @panic("should be a string!!\n"),
                    };

                    try DeStringify(new_entity, component_type_string, component_data_string);
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

fn Stringify(write_stream: *std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }), entity: Entity) !void {
    if (entity.HasComponent(IDComponent) == true) {
        const component = entity.GetComponent(IDComponent);

        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("IDComponent");
        try write_stream.write(component_string.items);
    }
    if (entity.HasComponent(SceneIDComponent) == true) {
        const component = entity.GetComponent(SceneIDComponent);

        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("SceneIDComponent");
        try write_stream.write(component_string.items);
    }
    if (entity.HasComponent(NameComponent) == true) {
        const component = entity.GetComponent(NameComponent);

        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("NameComponent");
        try write_stream.write(component_string.items);
    }
    if (entity.HasComponent(TransformComponent) == true) {
        const component = entity.GetComponent(TransformComponent);

        var buffer: [1000]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("TransformComponent");
        try write_stream.write(component_string.items);
    }
    if (entity.HasComponent(CameraComponent) == true) {
        const component = entity.GetComponent(CameraComponent);

        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("CameraComponent");
        try write_stream.write(component_string.items);
    }
    if (entity.HasComponent(CircleRenderComponent) == true) {
        const component = entity.GetComponent(CircleRenderComponent);

        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("CircleRenderComponent");
        try write_stream.write(component_string.items);
    }
    if (entity.HasComponent(SpriteRenderComponent) == true) {
        const component = entity.GetComponent(SpriteRenderComponent);

        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        var component_string = std.ArrayList(u8).init(fba.allocator());
        try std.json.stringify(component, .{}, component_string.writer());

        try write_stream.objectField("SpriteRenderComponent");
        try write_stream.write(component_string.items);
    }
}
fn DeStringify(entity: Entity, component_type_string: []const u8, component_string: []const u8) !void {
    if (std.mem.eql(u8, component_type_string, "IDComponent")) {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(IDComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        _ = try entity.AddComponent(IDComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, component_type_string, "SceneIDComponent")) {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(SceneIDComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        _ = try entity.AddComponent(SceneIDComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, component_type_string, "NameComponent")) {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(NameComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        _ = try entity.AddComponent(NameComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, component_type_string, "TransformComponent")) {
        var buffer: [1000]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(TransformComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        _ = try entity.AddComponent(TransformComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, component_type_string, "CameraComponent")) {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(CameraComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        _ = try entity.AddComponent(CameraComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, component_type_string, "CircleRenderComponent")) {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(CircleRenderComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        _ = try entity.AddComponent(CircleRenderComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, component_type_string, "SpriteRenderComponent")) {
        var buffer: [260]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const new_component_parsed = try std.json.parseFromSlice(SpriteRenderComponent, fba.allocator(), component_string, .{});
        defer new_component_parsed.deinit();
        const sprite_component = try entity.AddComponent(SpriteRenderComponent, new_component_parsed.value);
        sprite_component.mTexture = try AssetManager.GetAssetHandleRef("assets/textures/whitetexture.png");
    }
}
