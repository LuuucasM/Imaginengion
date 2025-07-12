const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const ECSManagerGameObj = @import("../Scene/SceneManager.zig").ECSManagerGameObj;
const Entity = @import("../GameObjects/Entity.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;

const EntityComponents = @import("../GameObjects/Components.zig");
const AISlotComponent = EntityComponents.AISlotComponent;
const CameraComponent = EntityComponents.CameraComponent;
const CircleRenderComponent = EntityComponents.CircleRenderComponent;
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const QuadComponent = EntityComponents.QuadComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const SpriteRenderComponent = EntityComponents.SpriteRenderComponent;
const TransformComponent = EntityComponents.TransformComponent;
const EntityScriptComponent = EntityComponents.ScriptComponent;
const EntityParentComponent = EntityComponents.ParentComponent;
const EntityChildComponent = EntityComponents.ChildComponent;
const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const ShaderAsset = @import("../Assets/Assets.zig").ShaderAsset;
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

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

pub fn SerializeSceneText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle) !void {
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

pub fn DeSerializeSceneText(scene_layer: SceneLayer, scene_asset: *SceneAsset, engine_allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var scanner = std.json.Scanner.initCompleteInput(allocator, scene_asset.mSceneContents.items);
    defer scanner.deinit();

    try DeSerializeSceneData(&scanner, scene_layer, allocator, engine_allocator);
}

pub fn SerializeSceneBinary(scene_layer: SceneLayer, scene_manager: SceneManager) void {
    //TODO
    _ = scene_layer;
    _ = scene_manager;
}

pub fn DeserializeSceneBinary(path: []const u8, scene_manager: SceneManager, allocator: std.mem.Allocator) SceneLayer {
    //TODO
    _ = path;
    _ = scene_manager;
    _ = allocator;
}

pub fn SerializeEntityText(entity: Entity, abs_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var out = std.ArrayList(u8).init(allocator);
    defer out.deinit();

    var write_stream = std.json.WriteStream(std.ArrayList(u8).Writer, .{ .checked_to_fixed_depth = 256 }).init(undefined, out.writer(), .{ .whitespace = .indent_2 });
    defer write_stream.deinit();

    try write_stream.beginObject();
    try SerializeEntity(&write_stream, entity, allocator);
    try write_stream.endObject();

    const file = try std.fs.createFileAbsolute(abs_path, .{ .read = false, .truncate = true });
    defer file.close();
    try file.writeAll(out.items);
}

pub fn DeSerializeEntityText(scene_layer: SceneLayer, abs_path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();

    const file_contents = try std.ArrayList(u8).initCapacity(allocator, file_size);
    file.readAll(file_contents.items);

    var scanner = std.json.Scanner.initCompleteInput(allocator, file_contents.items);
    defer scanner.deinit();

    const new_entity = try scene_layer.CreateBlankEntity();
    try DeSerializeEntity(&scanner, new_entity, scene_layer, allocator);
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
    const entity_list = try scene_layer.GetEntityGroup(.{ .Component = EntitySceneComponent }, allocator);
    defer entity_list.deinit();

    for (entity_list.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerGORef };
        if (entity.HasComponent(EntityChildComponent)) continue;

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try SerializeEntity(write_stream, entity, allocator);
        try write_stream.endObject();
    }
}

fn SerializeEntity(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    try SerializeCameraComponent(write_stream, entity, allocator);
    try SerializeBasicComponent(write_stream, entity, AISlotComponent, "AISlotComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, PlayerSlotComponent, "PlayerSlotComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, CircleRenderComponent, "CircleRenderComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, EntityIDComponent, "EntityIDComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, EntityNameComponent, "EntityNameComponent", allocator);
    try SerializeBasicComponent(write_stream, entity, TransformComponent, "TransformComponent", allocator);

    try SerializeSpriteRenderComponent(write_stream, entity, allocator);

    try SerializeQuadComponent(write_stream, entity, allocator);

    try SerializeScriptComponents(write_stream, entity, allocator);

    try SerializeParentComponent(write_stream, entity, allocator);
}

fn SerializeBasicComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8, allocator: std.mem.Allocator) !void {
    if (entity.HasComponent(component_type) == false) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

    try write_stream.objectField(field_name);
    const component = entity.GetComponent(component_type);
    try std.json.stringify(component, .{}, component_string.writer());
    try write_stream.write(component_string.items);
}

fn SerializeCameraComponent(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    if (entity.HasComponent(CameraComponent) == false) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

    const ecs = entity.mECSManagerRef;

    const component = ecs.GetComponent(CameraComponent, entity.mEntityID);

    try write_stream.objectField("CameraComponent");
    try write_stream.beginObject();

    try write_stream.objectField("ViewportWidth");
    try std.json.stringify(component.mViewportWidth, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("ViewportHeight");
    try std.json.stringify(component.mViewportHeight, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("Projection");
    try std.json.stringify(component.mProjection, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("AspectRatio");
    try std.json.stringify(component.mAspectRatio, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("IsFixedAspectRatio");
    try std.json.stringify(component.mIsFixedAspectRatio, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("PerspectiveFOVRad");
    try std.json.stringify(component.mPerspectiveFOVRad, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("PerspectiveNear");
    try std.json.stringify(component.mPerspectiveNear, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.objectField("PerspectiveFar");
    try std.json.stringify(component.mPerspectiveFar, .{}, component_string.writer());
    try write_stream.write(component_string.items);
    component_string.clearAndFree();

    try write_stream.endObject();
}

fn SerializeScriptComponents(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    if (entity.HasComponent(EntityScriptComponent) == false) return;

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
    if (entity.HasComponent(SpriteRenderComponent) == false) return;

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

fn SerializeQuadComponent(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) !void {
    if (entity.HasComponent(QuadComponent) == false) return;

    var component_string = ComponentString.init(allocator);
    defer component_string.deinit();

    try write_stream.objectField("QuadComponent");
    try write_stream.beginObject();

    try write_stream.objectField("Component");
    const component = entity.GetComponent(QuadComponent);
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

fn SerializeParentComponent(write_stream: *WriteStream, entity: Entity, allocator: std.mem.Allocator) anyerror!void {
    if (entity.HasComponent(EntityParentComponent) == false) return;

    const parent_component = entity.GetComponent(EntityParentComponent);
    var curr_id = parent_component.mFirstChild;

    while (curr_id != Entity.NullEntity) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

        try write_stream.objectField("Entity");

        try write_stream.beginObject();
        try SerializeEntity(write_stream, child_entity, allocator);
        try write_stream.endObject();

        const child_component = child_entity.GetComponent(EntityChildComponent);
        curr_id = child_component.mNext;
    }
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

fn DeSerializeSceneData(scanner: *std.json.Scanner, scene_layer: SceneLayer, allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const token_value = switch (token) {
            .string => |value| value,
            .allocated_string => |value| value,
            .number => |value| value,
            .allocated_number => |value| value,
            .object_begin => continue,
            .object_end => continue,
            .end_of_document => break,
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
            try DeSerializeEntity(scanner, new_entity, scene_layer, allocator, engine_allocator);
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
        else => return error.ExpectedString,
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

fn DeSerializeEntity(scanner: *std.json.Scanner, entity: Entity, scene_layer: SceneLayer, allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
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

        if (std.mem.eql(u8, actual_value, "CameraComponent")) {
            try DeSerializeCameraComponent(scanner, entity, allocator, engine_allocator);
        } else if (std.mem.eql(u8, actual_value, "CircleRenderComponent")) {
            try DeSerializeBasicComponent(scanner, entity, CircleRenderComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "AISlotComponent")) {
            try DeSerializeBasicComponent(scanner, entity, AISlotComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "PlayerSlotComponent")) {
            try DeSerializeBasicComponent(scanner, entity, PlayerSlotComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityIDComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityIDComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityNameComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityNameComponent, allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityScripts")) {
            try DeSerializeEntityScripts(scanner, entity, allocator);
        } else if (std.mem.eql(u8, actual_value, "QuadComponent")) {
            try DeSerializeQuadComponent(scanner, entity, allocator);
        } else if (std.mem.eql(u8, actual_value, "SpriteRenderComponent")) {
            try DeSerializeSpriteRenderComponent(scanner, entity, allocator);
        } else if (std.mem.eql(u8, actual_value, "TransformComponent")) {
            try DeSerializeTransformComponent(scanner, entity, allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            try DeSerializeParentComponent(scanner, entity, scene_layer, allocator, engine_allocator);
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

fn DeSerializeCameraComponent(scanner: *std.json.Scanner, entity: Entity, allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    // Skip past begin object token
    _ = try SkipToken(scanner, allocator);

    var camera_component = CameraComponent{};

    while (true) {
        const token = try scanner.nextAlloc(allocator, .alloc_if_needed);
        const token_value = switch (token) {
            .string => |value| value,
            .allocated_string => |value| value,
            .object_end => break,
            else => @panic("Unexpected token in CameraComponent deserialization"),
        };

        if (std.mem.eql(u8, token_value, "Projection")) {
            const projection_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const projection_string = switch (projection_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            const projection_parsed = try std.json.parseFromSlice(Mat4f32, allocator, projection_string, .{});
            defer projection_parsed.deinit();
            camera_component.mProjection = projection_parsed.value;
        } else if (std.mem.eql(u8, token_value, "ViewportWidth")) {
            const viewport_width_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const viewport_width_string = switch (viewport_width_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mViewportWidth = try std.fmt.parseUnsigned(usize, viewport_width_string, 10);
        } else if (std.mem.eql(u8, token_value, "ViewportHeight")) {
            const viewport_height_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const viewport_height_string = switch (viewport_height_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mViewportHeight = try std.fmt.parseUnsigned(usize, viewport_height_string, 10);
        } else if (std.mem.eql(u8, token_value, "AspectRatio")) {
            const aspect_ratio_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const aspect_ratio_string = switch (aspect_ratio_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mAspectRatio = try std.fmt.parseFloat(f32, aspect_ratio_string);
        } else if (std.mem.eql(u8, token_value, "IsFixedAspectRatio")) {
            const is_fixed_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const is_fixed_string = switch (is_fixed_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mIsFixedAspectRatio = std.mem.eql(u8, is_fixed_string, "true");
        } else if (std.mem.eql(u8, token_value, "PerspectiveFOVRad")) {
            const fov_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const fov_string = switch (fov_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mPerspectiveFOVRad = try std.fmt.parseFloat(f32, fov_string);
        } else if (std.mem.eql(u8, token_value, "PerspectiveNear")) {
            const persp_near_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const persp_near_string = switch (persp_near_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mPerspectiveNear = try std.fmt.parseFloat(f32, persp_near_string);
        } else if (std.mem.eql(u8, token_value, "PerspectiveFar")) {
            const persp_far_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
            const persp_far_string = switch (persp_far_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mPerspectiveFar = try std.fmt.parseFloat(f32, persp_far_string);
        }
    }

    camera_component.mViewportFrameBuffer = try FrameBuffer.Init(engine_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, camera_component.mViewportWidth, camera_component.mViewportHeight);
    camera_component.mViewportVertexArray = VertexArray.Init(engine_allocator);
    camera_component.mViewportVertexBuffer = VertexBuffer.Init(engine_allocator, @sizeOf([4][2]f32));
    camera_component.mViewportIndexBuffer = undefined;
    camera_component.mViewportShaderHandle = try AssetManager.GetAssetHandleRef("assets/shaders/SDFShader.glsl", .Eng);

    const shader_asset = try camera_component.mViewportShaderHandle.GetAsset(ShaderAsset);
    try camera_component.mViewportVertexBuffer.SetLayout(shader_asset.mShader.GetLayout());
    camera_component.mViewportVertexBuffer.SetStride(shader_asset.mShader.GetStride());

    var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
    camera_component.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

    var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
    camera_component.mViewportVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
    try camera_component.mViewportVertexArray.AddVertexBuffer(camera_component.mViewportVertexBuffer);
    camera_component.mViewportVertexArray.SetIndexBuffer(camera_component.mViewportIndexBuffer);

    camera_component.SetViewportSize(camera_component.mViewportWidth, camera_component.mViewportHeight);

    _ = try entity.AddComponent(CameraComponent, camera_component);
}

fn DeSerializeTransformComponent(scanner: *std.json.Scanner, entity: Entity, allocator: std.mem.Allocator) !void {
    const component_data_token = try scanner.nextAlloc(allocator, .alloc_if_needed);
    const component_data_string = switch (component_data_token) {
        .string => |v| v,
        .allocated_string => |v| v,
        else => return error.ExpectedString,
    };

    var new_component_parsed = try std.json.parseFromSlice(TransformComponent, allocator, component_data_string, .{});
    defer new_component_parsed.deinit();
    new_component_parsed.value.Dirty = true;
    _ = try entity.AddComponent(TransformComponent, new_component_parsed.value);
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

fn DeSerializeQuadComponent(scanner: *std.json.Scanner, entity: Entity, allocator: std.mem.Allocator) !void {
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
    const new_component_parsed = try std.json.parseFromSlice(QuadComponent, allocator, component_data_string, .{});
    defer new_component_parsed.deinit();

    const quad_component = try entity.AddComponent(QuadComponent, new_component_parsed.value);

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
    if (quad_component.mTexture.mID != AssetHandle.NullHandle) {
        const file_data_component = try std.json.parseFromSlice(FileMetaData, allocator, file_data_string, .{});
        defer file_data_component.deinit();
        const file_data = file_data_component.value;

        quad_component.mTexture = try AssetManager.GetAssetHandleRef(file_data.mRelPath, file_data.mPathType);
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

            try GameObjectUtils.AddScriptToEntity(entity, file_data.mRelPath, .Prj);
        }
        current_id = parsed_script_component.mNext;
    }

    //skip end of object token
    _ = try SkipToken(scanner, allocator);
}

fn DeSerializeParentComponent(scanner: *std.json.Scanner, entity: Entity, scene_layer: SceneLayer, allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) anyerror!void {
    if (entity.HasComponent(EntityParentComponent)) {
        try AddToExistingChildren(scanner, entity, scene_layer, allocator, engine_allocator);
    } else {
        try MakeEntityParent(scanner, entity, scene_layer, allocator, engine_allocator);
    }
}

fn AddToExistingChildren(scanner: *std.json.Scanner, parent_entity: Entity, scene_layer: SceneLayer, allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    const new_entity = try scene_layer.CreateBlankEntity();

    const parent_component = parent_entity.GetComponent(EntityParentComponent);
    var child_entity = Entity{ .mEntityID = parent_component.mFirstChild, .mECSManagerRef = parent_entity.mECSManagerRef };

    // Find the last child in the list
    var child_component = child_entity.GetComponent(EntityChildComponent);
    while (child_component.mNext != Entity.NullEntity) {
        child_entity.mEntityID = child_component.mNext;
        child_component = child_entity.GetComponent(EntityChildComponent);
    }

    // Add new entity to end of list
    const new_child_component = EntityChildComponent{
        .mFirst = child_component.mFirst,
        .mNext = Entity.NullEntity,
        .mParent = child_component.mParent,
        .mPrev = child_entity.mEntityID,
    };

    _ = try new_entity.AddComponent(EntityChildComponent, new_child_component);

    //set the new child component.mNext to be the new child
    child_component.mNext = new_entity.mEntityID;

    try DeSerializeEntity(scanner, new_entity, scene_layer, allocator, engine_allocator);
}

fn MakeEntityParent(scanner: *std.json.Scanner, parent_entity: Entity, scene_layer: SceneLayer, allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    const new_entity = try scene_layer.CreateBlankEntity();

    const new_parent_component = EntityParentComponent{ .mFirstChild = new_entity.mEntityID };
    _ = try parent_entity.AddComponent(EntityParentComponent, new_parent_component);

    const new_child_component = EntityChildComponent{
        .mFirst = new_entity.mEntityID,
        .mNext = Entity.NullEntity,
        .mParent = parent_entity.mEntityID,
        .mPrev = Entity.NullEntity,
    };
    _ = try new_entity.AddComponent(EntityChildComponent, new_child_component);

    try DeSerializeEntity(scanner, new_entity, scene_layer, allocator, engine_allocator);
}
