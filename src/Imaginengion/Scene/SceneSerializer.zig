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
const EntityParentComponent = EntityComponents.ParentComponent;
const EntityChildComponent = EntityComponents.ChildComponent;

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
const SceneType = SceneManager.SceneType;
const AssetType = AssetManager.AssetType;
const SceneAsset = Assets.SceneAsset;
const SceneUtils = @import("../Scene/SceneUtils.zig");

const WriteStream = std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 });
const ComponentString = std.ArrayList(u8);

pub fn SerializeText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var write_stream = std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }).init(undefined, out.writer(), .{ .whitespace = .indent_2 });
    defer write_stream.deinit();

    try SerializeSceneData(&write_stream, scene_layer, allocator);
    try WriteToFile(scene_asset_handle, out.items, allocator);
}

pub fn DeSerializeText(scene_layer: SceneLayer, scene_asset: *SceneAsset) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scanner = std.json.Scanner.initCompleteInput(allocator, scene_asset.mSceneContents.items);
    defer scanner.deinit();

    try DeSerializeSceneData(&scanner, scene_layer, allocator);
}

pub fn SerializeBinary(scene_layer: SceneLayer, scene_manager: SceneManager) void {
    //TODO
    _ = scene_layer;
    _ = scene_manager;
}

pub fn DeserializeBinary(path: []const u8, scene_manager: SceneManager, allocator: std.mem.Allocator) SceneLayer {
    //TODO
    _ = path;
    _ = scene_manager;
    _ = allocator;
}

fn FilterEntityByScene(ecs_manager_ref: *ECSManagerGameObj, entity_result_list: *std.ArrayList(Entity.Type), scene_id: SceneType) void {
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

fn SerializeSceneData(write_stream: *WriteStream, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    try write_stream.beginObject();

    try SerializeSceneMetaData(write_stream, scene_layer);

    try SerializeSceneScripts(write_stream, scene_layer, allocator);

    try SerializeSceneEntities(write_stream, scene_layer, allocator);

    try write_stream.endObject();
}

fn SerializeSceneMetaData(write_stream: *WriteStream, scene_layer: SceneLayer) !void {
    try write_stream.objectField("UUID");
    const scene_id_component = scene_layer.GetComponent(SceneIDComponent);
    try write_stream.write(scene_id_component.ID);

    try write_stream.objectField("LayerType");
    const scene_component = scene_layer.GetComponent(SceneComponent);
    try write_stream.write(scene_component.mLayerType);
}

fn SerializeSceneScripts(write_stream: *WriteStream, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    if (scene_layer.HasComponent(SceneScriptComponent) == false) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

    try write_stream.objectField("SceneScripts");
    try write_stream.beginObject();

    const ecs = scene_layer.mECSManagerSCRef;
    var current_id = scene_layer.mSceneID;

    while (current_id != SceneLayer.NullScene) {
        const component = ecs.GetComponent(SceneScriptComponent, current_id);

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

fn SerializeSceneEntities(write_stream: *WriteStream, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    var entity_list = try scene_layer.mECSManagerGORef.GetGroup(.{ .Component = EntitySceneComponent }, allocator);
    defer entity_list.deinit();

    FilterEntityByScene(scene_layer.mECSManagerGORef, &entity_list, scene_layer.mSceneID);

    for (entity_list.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerGORef };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try SerializeEntity(&write_stream, entity, allocator);
        try write_stream.endObject();
    }
}

fn SerializeEntity(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    try SerializeBasicComponent(write_stream, entity, CameraComponent, "CameraComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, EntityChildComponent, "EntityChildComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, ControllerComponent, "ControllerComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, CircleRenderComponent, "CircleRenderComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, EntityIDComponent, "EntityIDComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, EntityNameComponent, "EntityNameComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, TransformComponent, "TransformComponent", allocator);

    try SerializeScriptComponents(write_stream, entity, allocator);

    try SerializeSpriteRenderComponent(write_stream, entity, allocator);

    try SerializeParentComponent(write_stream, entity);
}

fn SerializeBasicComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8, allocator: std.mem.Allocator) !void {
    if (!entity.HasComponent(component_type) == false) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

    try write_stream.objectField(field_name);
    const component = entity.GetComponent(component_type);
    try std.json.stringify(component, .{}, component_string.writer());
    try write_stream.write(component_string.items);
}

fn SerializeScriptComponents(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    if (!entity.HasComponent(EntityScriptComponent)) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

    try write_stream.objectField("EntityScripts");
    try write_stream.beginObject();

    const ecs = entity.mECSManagerRef;
    var current_id = entity.mEntityID;
    while (current_id != Entity.NullEntity) {
        const component = ecs.GetComponent(EntityScriptComponent, current_id);

        try write_stream.objectField("Component");
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
        }

        current_id = component.mNext;
    }

    try write_stream.endObject();
}

fn SerializeSpriteRenderComponent(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    if (!entity.HasComponent(SpriteRenderComponent)) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

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
    }

    try write_stream.endObject();
}

fn SerializeParentComponent(write_stream: *WriteStream, entity: Entity) !void {
    if (!entity.HasComponent(EntityParentComponent)) return;

    try write_stream.objectField("ParentComponent");
    const parent_component = entity.GetComponent(EntityParentComponent);

    const child_entity = Entity{ .mEntityID = parent_component.mFirstChild, .mECSManagerRef = entity.mECSManagerRef };

    try write_stream.beginObject();
    SerializeEntity(write_stream, child_entity);
    try write_stream.endObject();
}

fn WriteToFile(scene_asset_handle: AssetHandle, data: []const u8, allocator: std.mem.Allocator) !void {
    const file_meta_data = try scene_asset_handle.GetAsset(FileMetaData);
    const file_abs_path = try AssetManager.GetAbsPath(file_meta_data.mRelPath, file_meta_data.mPathType, allocator);

    const file = try std.fs.createFileAbsolute(file_abs_path, .{ .read = false, .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn SkipToken(scanner: *std.json.Scanner, allocator: std.mem.Allocator) !void {
    _ = try scanner.nextAlloc(allocator, .alloc_if_needed);
}

fn DeSerializeSceneData(scanner: *std.json.Scanner, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const token_value = switch (token) {
            .string => |value| value,
            .allocated_string => |value| value,
            .number => |value| value,
            .allocated_number => |value| value,
            .object_begin => continue,
            .object_end => break,
            .end_of_document => @panic("This shouldnt happen!"),
            else => @panic("This shouldnt happen!"),
        };
        const actual_value = try allocator.dupe(u8, token_value);

        if (std.mem.eql(u8, actual_value, "UUID")) {
            try DeSerializeUUID(scanner, scene_layer, allocator);
        } else if (std.mem.eql(u8, actual_value, "LayerType")) {
            try DeSerializeLayerType(scanner, scene_layer, allocator);
        } else if (std.mem.eql(u8, actual_value, "SceneScripts")) {
            try DeSerializeSceneScripts(scanner, scene_layer, allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            const new_entity = try scene_layer.CreateBlankEntity();
            try DeSerializeEntity(scanner, new_entity, scene_layer, allocator);
        }
    }
}

fn DeSerializeUUID(scanner: *std.json.Scanner, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    const uuid_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
    const uuid_value = switch (uuid_token) {
        .number => |uuid_value| uuid_value,
        .allocated_number => |uuid_value| uuid_value,
        else => return error.ExpectedNumber,
    };
    scene_layer.GetComponent(SceneIDComponent).ID = try std.fmt.parseUnsigned(u128, uuid_value, 10);
}

fn DeSerializeLayerType(scanner: *std.json.Scanner, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    const layer_type_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
    const layer_type_value = switch (layer_type_token) {
        .string => |layer_type_value| layer_type_value,
        .allocated_string => |layer_type_value| layer_type_value,
        else => error.ExpectedString,
    };
    scene_layer.GetComponent(SceneComponent).mLayerType = std.meta.stringToEnum(LayerType, layer_type_value).?;
}

fn DeSerializeSceneScripts(scanner: *std.json.Scanner, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(scanner, allocator);

    var current_id = scene_layer.mSceneID;
    while (current_id != SceneLayer.NullScene) {
        //skip past object field called "component"
        _ = try SkipToken(scanner, allocator);

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

            try SceneUtils.AddScriptToScene(scene_layer, file_data.mRelPath, .Prj);
        }
        current_id = parsed_script_component.mNext;
    }
}

fn DeSerializeEntity(scanner: *std.json.Scanner, entity: Entity, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const token_value = switch (token) {
            .string => |value| value,
            .allocated_string => |value| value,
            .number => |value| value,
            .allocated_number => |value| value,
            .object_begin => continue,
            .object_end => break,
            .end_of_document => @panic("This shouldnt happen!"),
            else => @panic("This shouldnt happen!"),
        };
        const actual_value = try allocator.dupe(u8, token_value);

        if (std.mem.eql(u8, actual_value, "EntityChildComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityChildComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "CircleRenderComponent")) {
            try DeSerializeBasicComponent(scanner, entity, CircleRenderComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "ControllerComponent")) {
            try DeSerializeBasicComponent(scanner, entity, ControllerComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityIDComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityIDComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityNameComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityNameComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "TransformComponent")) {
            try DeSerializeBasicComponent(scanner, entity, TransformComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "CameraComponent")) {
            try DeSerializeBasicComponent(scanner, entity, CameraComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "SpriteRenderComponent")) {
            try DeSerializeSpriteRenderComponent(scanner, entity, allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityScripts")) {
            try DeSerializeEntityScripts(scanner, entity, allocator);
        } else if (std.mem.eql(u8, actual_value, "ParentComponent")) {
            try DeSerializeParentComponent(scanner, entity, scene_layer, allocator);
        }
    }
}

fn DeSerializeBasicComponent(scanner: *std.json.Scanner, entity: Entity, comptime component_type: type, allocator: std.mem.Allocator) !void {
    const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
    const component_data_string = switch (component_data_token) {
        .string => |v| v,
        .allocated_string => |v| v,
        else => return error.ExpectedString,
    };

    const new_component_parsed = try std.json.parseFromSlice(component_type, allocator, component_data_string, .{});
    defer new_component_parsed.deinit();
    _ = try entity.AddComponent(component_type, new_component_parsed.value);
}

fn DeSerializeSpriteRenderComponent(scanner: *std.json.Scanner, entity: Entity, allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(scanner, allocator);
    //skip past the object field token "Component"
    _ = try SkipToken(scanner, allocator);

    const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
    const component_data_string = switch (component_data_token) {
        .string => |component_data| component_data,
        .allocated_string => |component_data| component_data,
        else => @panic("should be a string!!\n"),
    };
    const new_component_parsed = try std.json.parseFromSlice(SpriteRenderComponent, allocator, component_data_string, .{});
    defer new_component_parsed.deinit();

    const sprite_render_component = try entity.AddComponent(SpriteRenderComponent, new_component_parsed.value);

    //skip past the object field token "FileMetaData"
    _ = try SkipToken(scanner, allocator);

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

    //skip past the end object token
    _ = try SkipToken(scanner, allocator);
}

fn DeSerializeEntityScripts(scanner: *std.json.Scanner, entity: Entity, allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(scanner, allocator);

    var current_id = entity.mEntityID;
    while (current_id != Entity.NullEntity) {
        //skip past object field called "component"
        _ = try SkipToken(scanner, allocator);

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
        _ = try SkipToken(scanner, allocator);

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

            try GameObjectUtils.AddScriptToEntity(entity.*, file_data.mRelPath, .Prj);
        }
        current_id = parsed_script_component.mNext;
    }

    //skip end of object token
    _ = try SkipToken(scanner, allocator);
}

fn DeSerializeParentComponent(scanner: *std.json.Scanner, entity: Entity, scene_layer: SceneLayer, allocator: std.mem.Allocator) !void {
    const child_entity = try scene_layer.CreateBlankEntity();
    entity.AddComponent(EntityParentComponent, EntityParentComponent{ .mFirstChild = child_entity.mEntityID });
    try DeSerializeEntity(scanner, child_entity, scene_layer, allocator);

    //skip end of object token
    _ = try SkipToken(scanner, allocator);
}
