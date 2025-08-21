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

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @import("../Renderer/Renderer.zig");

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

const WriteStream = std.json.Stringify;
const ComponentString = std.ArrayList(u8);

pub fn SerializeSceneText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle, frame_allocator: std.mem.Allocator) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .whitespace = .indent_2 } };

    try SerializeSceneData(&write_stream, scene_layer, frame_allocator);
    try WriteToFile(scene_asset_handle, out.written(), frame_allocator);
}

pub fn DeSerializeSceneText(scene_layer: SceneLayer, scene_asset: *SceneAsset, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    var scanner = std.json.Scanner.initCompleteInput(frame_allocator, scene_asset.mSceneContents.items);
    defer scanner.deinit();

    try DeSerializeSceneData(&scanner, scene_layer, frame_allocator, engine_allocator);
}

pub fn SerializeSceneBinary(scene_layer: SceneLayer, scene_manager: SceneManager, frame_allocator: std.mem.Allocator) void {
    //TODO
    _ = scene_layer;
    _ = scene_manager;
    _ = frame_allocator;
}

pub fn DeserializeSceneBinary(path: []const u8, scene_manager: SceneManager, frame_allocator: std.mem.Allocator) SceneLayer {
    //TODO
    _ = path;
    _ = scene_manager;
    _ = frame_allocator;
}

pub fn SerializeEntityText(entity: Entity, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .whitespace = .indent_2 } };

    try write_stream.beginObject();
    try SerializeEntity(&write_stream, entity);
    try write_stream.endObject();

    const file = try std.fs.createFileAbsolute(abs_path, .{ .read = false, .truncate = true });
    defer file.close();
    try file.writeAll(out.written());
}

pub fn DeSerializeEntityText(scene_layer: SceneLayer, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();

    const file_contents = try std.ArrayList(u8).initCapacity(frame_allocator, file_size);
    file.readAll(file_contents.items);

    var scanner = std.json.Scanner.initCompleteInput(frame_allocator, file_contents.items);
    defer scanner.deinit();

    const new_entity = try scene_layer.CreateBlankEntity();
    try DeSerializeEntity(&scanner, new_entity, scene_layer, frame_allocator);
}

fn SerializeSceneData(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    try write_stream.beginObject();

    try SerializeSceneMetaData(write_stream, scene_layer);

    try SerializeSceneScripts(write_stream, scene_layer, frame_allocator);

    try SerializeSceneEntities(write_stream, scene_layer, frame_allocator);

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

fn SerializeSceneScripts(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    if (scene_layer.HasComponent(SceneScriptComponent) == false) return;

    var component_string = ComponentString{};
    defer component_string.deinit(frame_allocator);

    try write_stream.objectField("SceneScripts");
    try write_stream.beginObject();

    const ecs = scene_layer.mECSManagerSCRef;
    var current_id = scene_layer.mSceneID;

    while (current_id != SceneLayer.NullScene) {
        const component = ecs.GetComponent(SceneScriptComponent, current_id);

        try write_stream.objectField("Component");
        try write_stream.write(component);

        try write_stream.objectField("AssetFileData");
        if (component.mScriptAssetHandle.mID != SceneLayer.NullScene) {
            const asset_file_data = try component.mScriptAssetHandle.GetAsset(FileMetaData);
            try write_stream.write(asset_file_data.mRelPath.items);
        } else {
            try write_stream.write("No Script Asset");
        }
        current_id = component.mNext;
    }
    try write_stream.endObject();
}

fn SerializeSceneEntities(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    var entity_list = try scene_layer.GetEntityGroup(.{ .Component = EntitySceneComponent }, frame_allocator);
    defer entity_list.deinit(frame_allocator);

    var child_list = try scene_layer.GetEntityGroup(.{ .Component = EntityChildComponent }, frame_allocator);
    defer child_list.deinit(frame_allocator);

    try scene_layer.EntityListDifference(&entity_list, child_list, frame_allocator);

    for (entity_list.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerGORef };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try SerializeEntity(write_stream, entity);
        try write_stream.endObject();
    }
}

fn SerializeEntity(write_stream: *WriteStream, entity: Entity) !void {
    try SerializeCameraComponent(write_stream, entity);
    try SerializeBasicComponent(write_stream, entity, AISlotComponent, "AISlotComponent");
    try SerializeBasicComponent(write_stream, entity, PlayerSlotComponent, "PlayerSlotComponent");
    try SerializeBasicComponent(write_stream, entity, EntityIDComponent, "EntityIDComponent");
    try SerializeBasicComponent(write_stream, entity, EntityNameComponent, "EntityNameComponent");
    try SerializeBasicComponent(write_stream, entity, TransformComponent, "TransformComponent");

    try SerializeQuadComponent(write_stream, entity);

    try SerializeScriptComponents(write_stream, entity);

    try SerializeParentComponent(write_stream, entity);
}

fn SerializeBasicComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8) !void {
    if (entity.HasComponent(component_type) == false) return;

    try write_stream.objectField(field_name);
    const component = entity.GetComponent(component_type);
    try write_stream.write(component);
}

fn SerializeCameraComponent(write_stream: *WriteStream, entity: Entity) !void {
    if (entity.HasComponent(CameraComponent) == false) return;

    const ecs = entity.mECSManagerRef;

    const component = ecs.GetComponent(CameraComponent, entity.mEntityID);

    try write_stream.objectField("CameraComponent");
    try write_stream.beginObject();

    try write_stream.objectField("ViewportWidth");
    try write_stream.write(component.mViewportWidth);

    try write_stream.objectField("ViewportHeight");
    try write_stream.write(component.mViewportHeight);

    try write_stream.objectField("Projection");
    try write_stream.write(component.mProjection);

    try write_stream.objectField("AspectRatio");
    try write_stream.write(component.mAspectRatio);

    try write_stream.objectField("IsFixedAspectRatio");
    try write_stream.write(component.mIsFixedAspectRatio);

    try write_stream.objectField("PerspectiveFOVRad");
    try write_stream.write(component.mPerspectiveFOVRad);

    try write_stream.objectField("PerspectiveNear");
    try write_stream.write(component.mPerspectiveNear);

    try write_stream.objectField("PerspectiveFar");
    try write_stream.write(component.mPerspectiveFar);

    try write_stream.endObject();
}

fn SerializeScriptComponents(write_stream: *WriteStream, entity: Entity) !void {
    if (entity.HasComponent(EntityScriptComponent) == false) return;

    try write_stream.objectField("EntityScripts");
    try write_stream.beginObject();

    const ecs = entity.mECSManagerRef;
    var current_id = entity.mEntityID;
    while (current_id != Entity.NullEntity) {
        const component = ecs.GetComponent(EntityScriptComponent, current_id);

        try write_stream.objectField("Component");
        try write_stream.write(component);

        try write_stream.objectField("AssetFileData");
        if (component.mScriptAssetHandle.mID != Entity.NullEntity) {
            const asset_file_data = try component.mScriptAssetHandle.GetAsset(FileMetaData);
            try write_stream.write(asset_file_data.mRelPath.items);
        } else {
            try write_stream.write("No Script Asset");
        }

        current_id = component.mNext;
    }

    try write_stream.endObject();
}

fn SerializeSpriteRenderComponent(write_stream: *WriteStream, entity: Entity, frame_allocator: std.mem.Allocator) !void {
    if (entity.HasComponent(SpriteRenderComponent) == false) return;

    var component_string = ComponentString.init(frame_allocator);
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

fn SerializeQuadComponent(write_stream: *WriteStream, entity: Entity) !void {
    if (entity.HasComponent(QuadComponent) == false) return;

    try write_stream.objectField("QuadComponent");
    try write_stream.beginObject();

    try write_stream.objectField("Component");
    const component = entity.GetComponent(QuadComponent);
    try write_stream.write(component);

    try write_stream.objectField("AssetFileData");
    if (component.mTexture.mID != AssetHandle.NullHandle) {
        const asset_file_data = try component.mTexture.GetAsset(FileMetaData);
        try write_stream.write(asset_file_data.mRelPath.items);
    } else {
        try write_stream.write("No Texture");
    }

    try write_stream.endObject();
}

fn SerializeParentComponent(write_stream: *WriteStream, entity: Entity) anyerror!void {
    if (entity.HasComponent(EntityParentComponent) == false) return;

    const parent_component = entity.GetComponent(EntityParentComponent);
    var curr_id = parent_component.mFirstChild;

    while (curr_id != Entity.NullEntity) {
        const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

        try write_stream.objectField("Entity");

        try write_stream.beginObject();
        try SerializeEntity(write_stream, child_entity);
        try write_stream.endObject();

        const child_component = child_entity.GetComponent(EntityChildComponent);
        curr_id = child_component.mNext;
    }
}

fn WriteToFile(scene_asset_handle: AssetHandle, data: []const u8, frame_allocator: std.mem.Allocator) !void {
    const file_meta_data = try scene_asset_handle.GetAsset(FileMetaData);
    const file_abs_path = try AssetManager.GetAbsPath(file_meta_data.mRelPath.items, file_meta_data.mPathType, frame_allocator);

    const file = try std.fs.createFileAbsolute(file_abs_path, .{ .read = false, .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn SkipToken(scanner: *std.json.Scanner, frame_allocator: std.mem.Allocator) !void {
    _ = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
}

fn DeSerializeSceneData(scanner: *std.json.Scanner, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
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
        const actual_value = try frame_allocator.dupe(u8, token_value);

        if (std.mem.eql(u8, actual_value, "UUID")) {
            try DeSerializeUUID(scanner, scene_layer, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "LayerType")) {
            try DeSerializeLayerType(scanner, scene_layer, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "SceneScripts")) {
            try DeSerializeSceneScripts(scanner, scene_layer, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            const new_entity = try scene_layer.CreateBlankEntity();
            try DeSerializeEntity(scanner, new_entity, scene_layer, frame_allocator, engine_allocator);
        }
    }
}

fn DeSerializeUUID(scanner: *std.json.Scanner, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const uuid_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
    const uuid_value = switch (uuid_token) {
        .number => |uuid_value| uuid_value,
        .allocated_number => |uuid_value| uuid_value,
        else => return error.ExpectedNumber,
    };
    scene_layer.GetComponent(SceneIDComponent).ID = try std.fmt.parseUnsigned(u128, uuid_value, 10);
}

fn DeSerializeLayerType(scanner: *std.json.Scanner, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const layer_type_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
    const layer_type_value = switch (layer_type_token) {
        .string => |layer_type_value| layer_type_value,
        .allocated_string => |layer_type_value| layer_type_value,
        else => return error.ExpectedString,
    };
    scene_layer.GetComponent(SceneComponent).mLayerType = std.meta.stringToEnum(LayerType, layer_type_value).?;
}

fn DeSerializeSceneScripts(scanner: *std.json.Scanner, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(scanner, frame_allocator);

    var current_id = scene_layer.mSceneID;
    while (current_id != SceneLayer.NullScene) {
        //skip past object field called "component"
        _ = try SkipToken(scanner, frame_allocator);

        const component_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        const new_component_parsed = try std.json.parseFromSlice(SceneScriptComponent, frame_allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        const parsed_script_component = new_component_parsed.value;

        //skip past the object field called "AssetFileData"
        _ = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);

        //read the next token which will be the potential path of the asset
        const file_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
        const file_data_string = switch (file_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        if (parsed_script_component.mScriptAssetHandle.mID != AssetHandle.NullHandle) {
            const file_data_component = try std.json.parseFromSlice([]const u8, frame_allocator, file_data_string, .{});
            defer file_data_component.deinit();
            const file_rel_path = file_data_component.value;

            try SceneUtils.AddScriptToScene(scene_layer, file_rel_path, .Prj);
        }
        current_id = parsed_script_component.mNext;
    }
}

fn DeSerializeEntity(scanner: *std.json.Scanner, entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
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
        const actual_value = try frame_allocator.dupe(u8, token_value);

        if (std.mem.eql(u8, actual_value, "CameraComponent")) {
            try DeSerializeCameraComponent(scanner, entity, frame_allocator, engine_allocator);
        } else if (std.mem.eql(u8, actual_value, "CircleRenderComponent")) {
            try DeSerializeBasicComponent(scanner, entity, CircleRenderComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "AISlotComponent")) {
            try DeSerializeBasicComponent(scanner, entity, AISlotComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "PlayerSlotComponent")) {
            try DeSerializeBasicComponent(scanner, entity, PlayerSlotComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityIDComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityIDComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityNameComponent")) {
            try DeSerializeBasicComponent(scanner, entity, EntityNameComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityScripts")) {
            try DeSerializeEntityScripts(scanner, entity, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "QuadComponent")) {
            try DeSerializeQuadComponent(scanner, entity, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "TransformComponent")) {
            try DeSerializeTransformComponent(scanner, entity, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            try DeSerializeParentComponent(scanner, entity, scene_layer, frame_allocator, engine_allocator);
        }
    }
}

fn DeSerializeBasicComponent(scanner: *std.json.Scanner, entity: Entity, comptime component_type: type, frame_allocator: std.mem.Allocator) !void {
    const component_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
    const component_data_string = switch (component_data_token) {
        .string => |v| v,
        .allocated_string => |v| v,
        else => return error.ExpectedString,
    };

    const new_component_parsed = try std.json.parseFromSlice(component_type, frame_allocator, component_data_string, .{});
    defer new_component_parsed.deinit();
    _ = try entity.AddComponent(component_type, new_component_parsed.value);
}

fn DeSerializeCameraComponent(scanner: *std.json.Scanner, entity: Entity, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    // Skip past begin object token
    _ = try SkipToken(scanner, frame_allocator);

    var camera_component = CameraComponent{};

    while (true) {
        const token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
        const token_value = switch (token) {
            .string => |value| value,
            .allocated_string => |value| value,
            .object_end => break,
            else => @panic("Unexpected token in CameraComponent deserialization"),
        };

        if (std.mem.eql(u8, token_value, "Projection")) {
            const projection_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const projection_string = switch (projection_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            const projection_parsed = try std.json.parseFromSlice(Mat4f32, frame_allocator, projection_string, .{});
            defer projection_parsed.deinit();
            camera_component.mProjection = projection_parsed.value;
        } else if (std.mem.eql(u8, token_value, "ViewportWidth")) {
            const viewport_width_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const viewport_width_string = switch (viewport_width_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mViewportWidth = try std.fmt.parseUnsigned(usize, viewport_width_string, 10);
        } else if (std.mem.eql(u8, token_value, "ViewportHeight")) {
            const viewport_height_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const viewport_height_string = switch (viewport_height_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mViewportHeight = try std.fmt.parseUnsigned(usize, viewport_height_string, 10);
        } else if (std.mem.eql(u8, token_value, "AspectRatio")) {
            const aspect_ratio_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const aspect_ratio_string = switch (aspect_ratio_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mAspectRatio = try std.fmt.parseFloat(f32, aspect_ratio_string);
        } else if (std.mem.eql(u8, token_value, "IsFixedAspectRatio")) {
            const is_fixed_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const is_fixed_string = switch (is_fixed_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mIsFixedAspectRatio = std.mem.eql(u8, is_fixed_string, "true");
        } else if (std.mem.eql(u8, token_value, "PerspectiveFOVRad")) {
            const fov_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const fov_string = switch (fov_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mPerspectiveFOVRad = try std.fmt.parseFloat(f32, fov_string);
        } else if (std.mem.eql(u8, token_value, "PerspectiveNear")) {
            const persp_near_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
            const persp_near_string = switch (persp_near_token) {
                .string => |v| v,
                .allocated_string => |v| v,
                else => return error.ExpectedString,
            };
            camera_component.mPerspectiveNear = try std.fmt.parseFloat(f32, persp_near_string);
        } else if (std.mem.eql(u8, token_value, "PerspectiveFar")) {
            const persp_far_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
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

    const shader_asset = try Renderer.GetSDFShader();
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

fn DeSerializeTransformComponent(scanner: *std.json.Scanner, entity: Entity, frame_allocator: std.mem.Allocator) !void {
    const component_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
    const component_data_string = switch (component_data_token) {
        .string => |v| v,
        .allocated_string => |v| v,
        else => return error.ExpectedString,
    };

    var new_component_parsed = try std.json.parseFromSlice(TransformComponent, frame_allocator, component_data_string, .{});
    defer new_component_parsed.deinit();
    new_component_parsed.value.Dirty = true;
    _ = try entity.AddComponent(TransformComponent, new_component_parsed.value);
}

fn DeSerializeQuadComponent(scanner: *std.json.Scanner, entity: Entity, frame_allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(scanner, frame_allocator);
    //skip past the object field token "Component"
    _ = try SkipToken(scanner, frame_allocator);

    const component_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
    const component_data_string = switch (component_data_token) {
        .string => |component_data| component_data,
        .allocated_string => |component_data| component_data,
        else => @panic("should be a string!!\n"),
    };
    const new_component_parsed = try std.json.parseFromSlice(QuadComponent, frame_allocator, component_data_string, .{});
    defer new_component_parsed.deinit();

    const quad_component = try entity.AddComponent(QuadComponent, new_component_parsed.value);

    //skip past the object field token "FileMetaData"
    _ = try SkipToken(scanner, frame_allocator);

    //read the next token which will be the potential path of the asset
    const file_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
    const file_data_string = switch (file_data_token) {
        .string => |component_data| component_data,
        .allocated_string => |component_data| component_data,
        else => @panic("should be a string!!\n"),
    };

    //if the spriterendercomponents asset handle id is not empty asset then request from asset manager the asset
    if (quad_component.mTexture.mID != AssetHandle.NullHandle) {
        const file_data_component = try std.json.parseFromSlice([]const u8, frame_allocator, file_data_string, .{});
        defer file_data_component.deinit();
        const file_rel_path = file_data_component.value;

        quad_component.mTexture = try AssetManager.GetAssetHandleRef(file_rel_path, .Prj);
    }

    //skip past the end object token
    _ = try SkipToken(scanner, frame_allocator);
}

fn DeSerializeEntityScripts(scanner: *std.json.Scanner, entity: Entity, frame_allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(scanner, frame_allocator);

    var current_id = entity.mEntityID;
    while (current_id != Entity.NullEntity) {
        //skip past object field called "component"
        _ = try SkipToken(scanner, frame_allocator);

        const component_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        const new_component_parsed = try std.json.parseFromSlice(EntityScriptComponent, frame_allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        const parsed_script_component = new_component_parsed.value;

        //skip past the object field called "AssetFileData"
        _ = try SkipToken(scanner, frame_allocator);

        //read the next token which will be the potential path of the asset
        const file_data_token = try scanner.nextAlloc(frame_allocator, .alloc_if_needed);
        const file_data_string = switch (file_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        if (parsed_script_component.mScriptAssetHandle.mID != AssetHandle.NullHandle) {
            const file_data_component = try std.json.parseFromSlice([]const u8, frame_allocator, file_data_string, .{});
            defer file_data_component.deinit();
            const file_rel_path = file_data_component.value;

            try GameObjectUtils.AddScriptToEntity(entity, file_rel_path, .Prj);
        }
        current_id = parsed_script_component.mNext;
    }

    //skip end of object token
    _ = try SkipToken(scanner, frame_allocator);
}

fn DeSerializeParentComponent(scanner: *std.json.Scanner, entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) anyerror!void {
    if (entity.HasComponent(EntityParentComponent)) {
        try AddToExistingChildren(scanner, entity, scene_layer, frame_allocator, engine_allocator);
    } else {
        try MakeEntityParent(scanner, entity, scene_layer, frame_allocator, engine_allocator);
    }
}

fn AddToExistingChildren(scanner: *std.json.Scanner, parent_entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
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

    try DeSerializeEntity(scanner, new_entity, scene_layer, frame_allocator, engine_allocator);
}

fn MakeEntityParent(scanner: *std.json.Scanner, parent_entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
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

    try DeSerializeEntity(scanner, new_entity, scene_layer, frame_allocator, engine_allocator);
}
