const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const ECSManagerGameObj = @import("../Scene/SceneManager.zig").ECSManagerGameObj;
const Entity = @import("../GameObjects/Entity.zig");

const EntityComponents = @import("../GameObjects/Components.zig");
const CameraComponent = EntityComponents.CameraComponent;
const CircleRenderComponent = EntityComponents.CircleRenderComponent;
const ControllerComponent = EntityComponents.ControllerComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const SpriteRenderComponent = EntityComponents.SpriteRenderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const PrimaryCameraTag = EntityComponents.PrimaryCameraTag;

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneIDComponent = SceneComponents.IDComponent;
const SceneComponent = SceneComponents.SceneComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;

const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const AssetManager = @import("../Assets/AssetManager.zig");
const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const FileMetaData = Assets.FileMetaData;
const SceneManager = @import("SceneManager.zig");
const EntityType = SceneManager.EntityType;
const SceneType = SceneManager.SceneType;
const AssetType = AssetManager.AssetType;
const SceneAsset = Assets.SceneAsset;

pub fn SerializeText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var write_stream = std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }).init(undefined, out.writer(), .{ .whitespace = .indent_2 });
    defer write_stream.deinit();

    try write_stream.beginObject();

    try write_stream.objectField("UUID");
    const scene_id_component = scene_layer.GetComponent(SceneIDComponent);
    try write_stream.write(scene_id_component.ID);

    try write_stream.objectField("LayerType");
    const scene_component = scene_layer.GetComponent(SceneComponent);
    try write_stream.write(scene_component.mLayerType);

    //scene scripts
    if (scene_layer.HasComponent(SceneScriptComponent)) {
        var component_string = std.ArrayList(u8).init(allocator);
        defer component_string.deinit();
        try write_stream.objectField("SceneScripts");

        try write_stream.beginObject();

        const ecs = scene_layer.mECSManagerSCRef;
        var current_id = scene_layer.mSceneID;
        var component: *SceneScriptComponent = undefined;
        while (current_id != SceneLayer.NullScene) {
            component = ecs.GetComponent(SceneScriptComponent, current_id);

            try write_stream.objectField("Component");
            try std.json.stringify(component, .{}, component_string.writer());
            try write_stream.write(component_string.items);
            component_string.clearAndFree();

            try write_stream.objectField("AssetFileData");
            if (component.mScriptAssetHandle.mID != SceneLayer.NullScene) {
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

    //scene entities
    var entity_list = try scene_layer.mECSManagerGORef.GetGroup(.{ .Component = EntitySceneComponent }, allocator);

    FilterEntityByScene(scene_layer.mECSManagerGORef, &entity_list, scene_layer.mSceneID);

    for (entity_list.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerGORef };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try Stringify(&write_stream, entity);
        try write_stream.endObject();
    }
    try write_stream.endObject();

    const file_meta_data = try scene_asset_handle.GetAsset(FileMetaData);
    const file_abs_path = try AssetManager.GetAbsPath(file_meta_data.mRelPath, file_meta_data.mPathType, allocator);

    const file = try std.fs.createFileAbsolute(
        file_abs_path,
        .{ .read = false, .truncate = true },
    );
    defer file.close();
    try file.writeAll(out.items);
}

pub fn DeSerializeText(scene_layer: SceneLayer, scene_asset: *SceneAsset) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scanner = std.json.Scanner.initCompleteInput(allocator, scene_asset.mSceneContents.items);
    defer scanner.deinit();

    var entity = Entity{ .mEntityID = Entity.NullEntity, .mECSManagerRef = scene_layer.mECSManagerGORef };

    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const value = switch (token) {
            .string => |value| value,
            .allocated_string => |value| value,
            .number => |value| value,
            .allocated_number => |value| value,
            .object_begin => continue,
            .object_end => continue,
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
    if (entity.HasComponent(CameraComponent) == true) {
        try write_stream.objectField("CameraComponent");

        try write_stream.beginObject();

        try write_stream.objectField("Component");
        const component = entity.GetComponent(CameraComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);
        component_string.clearAndFree();

        try write_stream.objectField("IsPrimary");
        if (entity.HasComponent(PrimaryCameraTag) == true) {
            try write_stream.write("True");
        } else {
            try write_stream.write("False");
        }
        try write_stream.endObject();
    }
    if (entity.HasComponent(ControllerComponent) == true) {
        try write_stream.objectField("ControllerComponent");

        const component = entity.GetComponent(ControllerComponent);
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
    if (entity.HasComponent(EntityIDComponent) == true) {
        try write_stream.objectField("EntityIDComponent");

        const component = entity.GetComponent(EntityIDComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(EntityNameComponent) == true) {
        try write_stream.objectField("NameComponent");

        const component = entity.GetComponent(EntityNameComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
    if (entity.HasComponent(EntityScriptComponent) == true) {
        try write_stream.objectField("EntityScripts");

        try write_stream.beginObject();

        const ecs = entity.mECSManagerRef;
        var current_id = entity.mEntityID;
        var component: *EntityScriptComponent = undefined;
        while (current_id != Entity.NullEntity) {
            try write_stream.objectField("Component");

            component = ecs.GetComponent(EntityScriptComponent, current_id);
            try std.json.stringify(component, .{}, component_string.writer());
            try write_stream.write(component_string.items);
            component_string.clearAndFree();

            try write_stream.objectField("AssetFileData");
            if (component.mScriptAssetHandle.mID != Entity.NullEntity) {
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
    if (entity.HasComponent(SpriteRenderComponent) == true) {
        try write_stream.objectField("SpriteRenderComponent");

        try write_stream.beginObject();

        try write_stream.objectField("Component");
        const component = entity.GetComponent(SpriteRenderComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);
        component_string.clearAndFree();

        try write_stream.objectField("AssetFileData");
        if (component.mTexture.mID != AssetHandle.NullHandle) {
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
    if (entity.HasComponent(TransformComponent) == true) {
        try write_stream.objectField("TransformComponent");

        const component = entity.GetComponent(TransformComponent);
        try std.json.stringify(component, .{}, component_string.writer());
        try write_stream.write(component_string.items);

        component_string.clearAndFree();
    }
}

fn Destringify(allocator: std.mem.Allocator, value: []const u8, scanner: *std.json.Scanner, scene_layer: SceneLayer, current_entity: *Entity) !void {
    if (std.mem.eql(u8, value, "UUID") == true) {
        const uuid_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const uuid_value = switch (uuid_token) {
            .number => |uuid_value| uuid_value,
            .allocated_number => |uuid_value| uuid_value,
            else => @panic("should be a number!\n"),
        };
        scene_layer.GetComponent(SceneIDComponent).ID = try std.fmt.parseUnsigned(u128, uuid_value, 10);
    } else if (std.mem.eql(u8, value, "LayerType") == true) {
        const layer_type_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const layer_type_value = switch (layer_type_token) {
            .string => |layer_type_value| layer_type_value,
            .allocated_string => |layer_type_value| layer_type_value,
            else => @panic("Should be a string!\n"),
        };
        scene_layer.GetComponent(SceneComponent).mLayerType = std.meta.stringToEnum(LayerType, layer_type_value).?;
    } else if (std.mem.eql(u8, value, "Entity")) {
        current_entity.* = try scene_layer.CreateBlankEntity();
    } else if (std.mem.eql(u8, value, "CameraComponent")) {
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
        const new_component_parsed = try std.json.parseFromSlice(CameraComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(CameraComponent, new_component_parsed.value);

        //skip past object field token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

        const is_primary_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const is_primary_data_string = switch (is_primary_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        if (std.mem.eql(u8, is_primary_data_string, "True") == true) {
            _ = try current_entity.AddComponent(PrimaryCameraTag, null);
        }
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
    } else if (std.mem.eql(u8, value, "ControllerComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(ControllerComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(ControllerComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "EntityIDComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(EntityIDComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(EntityIDComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "EntityNameComponent")) {
        const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };
        const new_component_parsed = try std.json.parseFromSlice(EntityNameComponent, allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        _ = try current_entity.AddComponent(EntityNameComponent, new_component_parsed.value);
    } else if (std.mem.eql(u8, value, "EntityScripts")) {
        //skip past begin object token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

        var current_id = current_entity.mEntityID;
        while (current_id != Entity.NullEntity) {
            //skip past object field called "component"
            _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

            const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const component_data_string = switch (component_data_token) {
                .string => |component_data| component_data,
                .allocated_string => |component_data| component_data,
                else => @panic("should be a string!!\n"),
            };
            const new_component_parsed = try std.json.parseFromSlice(EntityScriptComponent, allocator, component_data_string, .{});
            defer new_component_parsed.deinit();

            const parsed_script_component = new_component_parsed.value;

            //skip past the object field called "AssetFileData"
            _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

            //read the next token which will be the potential path of the asset
            const file_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const file_data_string = switch (file_data_token) {
                .string => |component_data| component_data,
                .allocated_string => |component_data| component_data,
                else => @panic("should be a string!!\n"),
            };

            if (parsed_script_component.mScriptAssetHandle.mID != AssetHandle.NullHandle) {
                const file_data_component = try std.json.parseFromSlice(FileMetaData, allocator, file_data_string, .{});
                defer file_data_component.deinit();
                const file_data = file_data_component.value;

                try GameObjectUtils.AddScriptToEntity(current_entity.*, file_data.mRelPath, .Prj);
            }
            current_id = parsed_script_component.mNext;
        }
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
        if (sprite_render_component.mTexture.mID != AssetHandle.NullHandle) {
            const file_data_component = try std.json.parseFromSlice(FileMetaData, allocator, file_data_string, .{});
            defer file_data_component.deinit();
            const file_data = file_data_component.value;

            sprite_render_component.mTexture = try AssetManager.GetAssetHandleRef(file_data.mRelPath, file_data.mPathType);
        }
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
    } else if (std.mem.eql(u8, value, "SceneScripts")) {
        //skip past begin object token
        _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

        var current_id = scene_layer.mSceneID;
        while (current_id != SceneLayer.NullScene) {
            //skip past object field called "component"
            _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

            const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const component_data_string = switch (component_data_token) {
                .string => |component_data| component_data,
                .allocated_string => |component_data| component_data,
                else => @panic("should be a string!!\n"),
            };
            const new_component_parsed = try std.json.parseFromSlice(SceneScriptComponent, allocator, component_data_string, .{});
            defer new_component_parsed.deinit();

            const parsed_script_component = new_component_parsed.value;

            //skip past the object field called "AssetFileData"
            _ = try scanner.nextAlloc(allocator, .alloc_if_needed);

            //read the next token which will be the potential path of the asset
            const file_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const file_data_string = switch (file_data_token) {
                .string => |component_data| component_data,
                .allocated_string => |component_data| component_data,
                else => @panic("should be a string!!\n"),
            };

            if (parsed_script_component.mScriptAssetHandle.mID != AssetHandle.NullHandle) {
                const file_data_component = try std.json.parseFromSlice(FileMetaData, allocator, file_data_string, .{});
                defer file_data_component.deinit();
                const file_data = file_data_component.value;

                try GameObjectUtils.AddScriptToEntity(current_entity.*, file_data.mRelPath, .Prj);
            }
            current_id = parsed_script_component.mNext;
        }
    }
}

pub fn FilterEntityByScene(ecs_manager_ref: *ECSManagerGameObj, entity_result_list: *std.ArrayList(EntityType), scene_id: SceneType) void {
    if (entity_result_list.items.len == 0) return;

    var end_index: usize = entity_result_list.items.len;
    var i: usize = 0;

    while (i < end_index) {
        const entity_scene_component = ecs_manager_ref.GetComponent(EntitySceneComponent, entity_result_list.items[i]);
        if (entity_scene_component.SceneID != scene_id) {
            entity_result_list.items[i] = entity_result_list.items[end_index - 1];
            end_index -= 1;
        } else {
            i += 1;
        }
    }

    entity_result_list.shrinkAndFree(end_index);
}
