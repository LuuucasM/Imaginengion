const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = SceneLayer.LayerType;
const Entity = @import("../GameObjects/Entity.zig");

const ECSManager = @import("../ECS/ECSManager.zig");
const Components = @import("../GameObjects/Components.zig");
const CameraComponent = Components.CameraComponent;
const CircleRenderComponent = Components.CircleRenderComponent;
const IDComponent = Components.IDComponent;
const NameComponent = Components.NameComponent;
const SceneIDComponent = Components.SceneIDComponent;
const SpriteRenderComponent = Components.SpriteRenderComponent;
const TransformComponent = Components.TransformComponent;
const ScriptComponent = Components.ScriptComponent;

//component tags
const OnKeyPressedScript = Components.OnKeyPressedScript;
const OnUpdateInputScript = Components.OnUpdateInputScript;

const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const AssetManager = @import("../Assets/AssetManager.zig");
const Assets = @import("../Assets/Assets.zig");
const FileMetaData = Assets.FileMetaData;
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

    var group = try scene_layer.mECSManagerRef.GetGroup(.{ .Component = SceneIDComponent }, allocator);
    FilterSceneUUID(&group, scene_layer.mUUID, scene_layer.mECSManagerRef);
    for (group.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerRef };

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

    var entity = Entity{ .mEntityID = std.math.maxInt(u32), .mECSManagerRef = scene_layer.mECSManagerRef };

    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const value = switch (token) {
            .string => |value| value,
            .number => |value| value,
            .object_begin => continue,
            .object_end => continue,
            //.allocated_string => |value| value,
            //.allocated_number => |value| value,
            .end_of_document => break,
            else => @panic("This shouldnt happen!"),
        };

        const actual_value = try allocator.dupe(u8, value);
        try Destringify(allocator, actual_value, &scanner, scene_layer, &entity);
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var component_string = std.ArrayList(u8).init(allocator);
    defer component_string.deinit();

    if (entity.HasComponent(IDComponent) == true) {
        try write_stream.objectField("IDComponent");

        const component = entity.GetComponent(IDComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(SceneIDComponent) == true) {
        try write_stream.objectField("SceneIDComponent");

        const component = entity.GetComponent(SceneIDComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(NameComponent) == true) {
        try write_stream.objectField("NameComponent");

        const component = entity.GetComponent(NameComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(TransformComponent) == true) {
        try write_stream.objectField("TransformComponent");

        const component = entity.GetComponent(TransformComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(CameraComponent) == true) {
        try write_stream.objectField("CameraComponent");

        const component = entity.GetComponent(CameraComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(CircleRenderComponent) == true) {
        try write_stream.objectField("CircleRenderComponent");

        const component = entity.GetComponent(CircleRenderComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(SpriteRenderComponent) == true) {
        try write_stream.objectField("SpriteRenderComponent");

        try write_stream.beginObject();

        try write_stream.objectField("Component");
        const component = entity.GetComponent(SpriteRenderComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);
        component_string.clearAndFree();

        try write_stream.objectField("AssetFileData");
        if (component.mTexture.mID != std.math.maxInt(u32)) {
            const asset_file_data = try component.mTexture.GetAsset(FileMetaData);
            try std.json.stringify(asset_file_data, .{}, component_string.writer());
            try write_stream.write(component_string.items);
            component_string.clearAndFree();
        } else {
            try write_stream.write("No Texture");
            component_string.clearAndFree();
        }

        try write_stream.endObject();
    }
    if (entity.HasComponent(ScriptComponent) == true) {
        try write_stream.objectField("ScriptComponent");

        try write_stream.beginObject();

        const ecs = entity.mECSManagerRef;
        var current_id = entity.mEntityID;
        var component: *ScriptComponent = undefined;
        while (current_id != std.math.maxInt(u32)) {
            try write_stream.objectField("Component");

            component = ecs.GetComponent(ScriptComponent, current_id);
            try std.json.stringify(component, .{}, component_string.writer());
            try write_stream.write(component_string.items);
            component_string.clearAndFree();

            try write_stream.objectField("AssetFileData");
            if (component.mScriptAssetHandle.mID != std.math.maxInt(u32)) {
                const asset_file_data = try component.mScriptAssetHandle.GetAsset(FileMetaData);
                try std.json.stringify(asset_file_data, .{}, component_string.writer());
                try write_stream.write(component_string.items);
                component_string.clearAndFree();
            } else {
                try write_stream.write("No Script Asset");
                component_string.clearAndFree();
            }

            current_id = component.mNext;
        }

        try write_stream.endObject();
    }
}

fn Destringify(allocator: std.mem.Allocator, value: []const u8, scanner: *std.json.Scanner, scene_layer: *SceneLayer, current_entity: *Entity) !void {
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
    } else if (std.mem.eql(u8, value, "Entity")) {
        current_entity.* = try scene_layer.CreateBlankEntity();
    } else if (std.mem.eql(u8, value, "IDComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(IDComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(IDComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "SceneIDComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(SceneIDComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(SceneIDComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "NameComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(NameComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(NameComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "TransformComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(TransformComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(TransformComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "CameraComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(CameraComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(CameraComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "CircleRenderComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(CircleRenderComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(CircleRenderComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "SpriteRenderComponent")) {
        //skip past begin object token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);
        //skip past the object field token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(SpriteRenderComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();

        const sprite_render_component = try current_entity.AddComponent(SpriteRenderComponent, new_component_parsed.value);

        //skip past the object field token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

        //read the next token which will be the potential path of the asset
        const file_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const file_data_string = switch (file_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        //if the spriterendercomponents asset handle id is not empty asset then request from asset manager the asset
        if (sprite_render_component.mTexture.mID != std.math.maxInt(u32)) {
            const file_data_component = try std.json.parseFromSlice(FileMetaData, allocator, file_data_string, .{});
            defer file_data_component.deinit();
            const file_data = file_data_component.value;

            sprite_render_component.mTexture = try AssetManager.GetAssetHandleRef(file_data.mRelPath, file_data.mPathType);
        }
    } else if (std.mem.eql(u8, value, "ScriptComponent")) {
        //skip past begin object token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

        var current_id: u32 = current_entity.mEntityID;
        while (current_id != std.math.maxInt(u32)) {
            //skip past object field
            _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

            const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const component_data_string = switch (component_data_token) {
                .string => |component_data| component_data,
                .allocated_string => |component_data| component_data,
                else => @panic("should be a string!!\n"),
            };
            const new_component_parsed = try std.json.parseFromSlice(ScriptComponent, allocator, component_data_string, .{});
            defer new_component_parsed.deinit();

            const parsed_script_component = new_component_parsed.value;

            //skip past the object field token
            _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

            //read the next token which will be the potential path of the asset
            const file_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const file_data_string = switch (file_data_token) {
                .string => |component_data| component_data,
                .allocated_string => |component_data| component_data,
                else => @panic("should be a string!!\n"),
            };

            if (parsed_script_component.mScriptAssetHandle.mID != std.math.maxInt(u32)) {
                const file_data_component = try std.json.parseFromSlice(FileMetaData, allocator, file_data_string, .{});
                defer file_data_component.deinit();
                const file_data = file_data_component.value;

                try GameObjectUtils.AddScriptToEntity(current_entity.*, file_data.mRelPath);
            }
            current_id = parsed_script_component.mNext;
        }
    }
}

fn FilterSceneUUID(result: *std.ArrayList(u32), scene_uuid: u128, ecs_manager: *ECSManager) void {
    if (result.items.len == 0) return;

    var end_index: usize = result.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const scene_id_component = ecs_manager.GetComponent(SceneIDComponent, result.items[i]);
        if (scene_id_component.SceneID != scene_uuid) {
            result.items[i] = result.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    result.shrinkAndFree(end_index);
}
