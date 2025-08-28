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
const EntityIDComponent = EntityComponents.IDComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const QuadComponent = EntityComponents.QuadComponent;
const EntitySceneComponent = EntityComponents.SceneIDComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
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
const SceneTransformComponent = SceneComponents.TransformComponent;

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
const StringifyOptions = std.json.Stringify.Options{ .whitespace = .indent_2 };
const PraseOptions = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

pub fn SerializeSceneText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle, frame_allocator: std.mem.Allocator) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

    try SerializeSceneData(&write_stream, scene_layer, frame_allocator);
    try WriteToFile(scene_asset_handle, out.written(), frame_allocator);
}

pub fn DeSerializeSceneText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    const scene_asset = try scene_asset_handle.GetAsset(SceneAsset);

    var io_reader = std.io.Reader.fixed(scene_asset.mSceneContents.items);
    var json_reader = std.json.Reader.init(frame_allocator, &io_reader);
    defer json_reader.deinit();

    try DeSerializeSceneData(&json_reader, scene_layer, frame_allocator, engine_allocator, scene_asset_handle);
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

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

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

    var io_reader = std.io.Reader.fixed(file_contents.items);

    var reader = std.json.Reader.init(frame_allocator, &io_reader);
    defer reader.deinit();

    const new_entity = try scene_layer.CreateBlankEntity();
    try DeSerializeEntity(&reader, new_entity, scene_layer, frame_allocator);
}

fn SerializeSceneData(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    try write_stream.beginObject();

    try SerializeSceneMetaData(write_stream, scene_layer);

    try SerializeSceneScripts(write_stream, scene_layer);

    try SerializeSceneEntities(write_stream, scene_layer, frame_allocator);

    try write_stream.endObject();
}

fn SerializeSceneMetaData(write_stream: *WriteStream, scene_layer: SceneLayer) !void {
    try write_stream.objectField("SceneID");
    const scene_id_component = scene_layer.GetComponent(SceneIDComponent).?;
    try write_stream.write(scene_id_component);

    try write_stream.objectField("SceneData");
    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    try write_stream.write(scene_component);

    try write_stream.objectField("Transform");
    const scene_transform = scene_layer.GetComponent(SceneTransformComponent).?;
    try write_stream.write(scene_transform);
}

fn SerializeSceneScripts(write_stream: *WriteStream, scene_layer: SceneLayer) !void {
    if (scene_layer.HasComponent(SceneScriptComponent) == false) return;

    try write_stream.objectField("SceneScripts");
    try write_stream.beginObject();

    const ecs = scene_layer.mECSManagerSCRef;
    var current_id = scene_layer.mSceneID;

    while (current_id != SceneLayer.NullScene) {
        const script_component = ecs.GetComponent(SceneScriptComponent, current_id).?;

        try write_stream.objectField("Script");
        try write_stream.write(script_component);

        current_id = script_component.mNext;
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
    try SerializeBasicComponent(write_stream, entity, CameraComponent, "CameraComponent");
    try SerializeBasicComponent(write_stream, entity, AISlotComponent, "AISlotComponent");
    try SerializeBasicComponent(write_stream, entity, PlayerSlotComponent, "PlayerSlotComponent");
    try SerializeBasicComponent(write_stream, entity, EntityIDComponent, "EntityIDComponent");
    try SerializeBasicComponent(write_stream, entity, EntityNameComponent, "EntityNameComponent");
    try SerializeBasicComponent(write_stream, entity, EntityTransformComponent, "TransformComponent");
    try SerializeBasicComponent(write_stream, entity, QuadComponent, "QuadComponent");

    try SerializeScriptComponents(write_stream, entity);

    try SerializeParentComponent(write_stream, entity);
}

fn SerializeBasicComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8) !void {
    if (entity.GetComponent(component_type)) |component| {
        try write_stream.objectField(field_name);
        try write_stream.write(component);
    }
}

fn SerializeScriptComponents(write_stream: *WriteStream, entity: Entity) !void {
    if (entity.GetComponent(EntityScriptComponent) != null) {
        try write_stream.objectField("EntityScripts");
        try write_stream.beginObject();

        const ecs = entity.mECSManagerRef;
        var current_id = entity.mEntityID;
        while (current_id != Entity.NullEntity) {
            const script_component = ecs.GetComponent(EntityScriptComponent, current_id).?;

            try write_stream.objectField("Script");
            try write_stream.write(script_component);

            current_id = script_component.mNext;
        }

        try write_stream.endObject();
    }
}

fn SerializeParentComponent(write_stream: *WriteStream, entity: Entity) anyerror!void {
    if (entity.GetComponent(EntityParentComponent)) |parent_component| {
        var curr_id = parent_component.mFirstChild;

        while (curr_id != Entity.NullEntity) {
            const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

            try write_stream.objectField("Entity");

            try write_stream.beginObject();
            try SerializeEntity(write_stream, child_entity);
            try write_stream.endObject();

            const child_component = child_entity.GetComponent(EntityChildComponent).?;
            curr_id = child_component.mNext;
        }
    }
}

fn WriteToFile(scene_asset_handle: AssetHandle, data: []const u8, frame_allocator: std.mem.Allocator) !void {
    const file_meta_data = try scene_asset_handle.GetAsset(FileMetaData);
    const file_abs_path = try AssetManager.GetAbsPath(file_meta_data.mRelPath.items, file_meta_data.mPathType, frame_allocator);

    const file = try std.fs.createFileAbsolute(file_abs_path, .{ .read = false, .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}

fn DeSerializeSceneData(reader: *std.json.Reader, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator, scene_asset_handle: AssetHandle) !void {
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .end_of_document => break,
            .object_begin => continue,
            .object_end => continue,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try frame_allocator.dupe(u8, token_value);
        defer frame_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "SceneID")) {
            try DeSerializeUUID(reader, scene_layer, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "SceneData")) {
            try DeSerializeSceneDataComponent(reader, scene_layer, frame_allocator, scene_asset_handle);
        } else if (std.mem.eql(u8, actual_value, "Transform")) {
            try DeserializeSceneTransform(reader, scene_layer, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "SceneScripts")) {
            try DeSerializeSceneScripts(reader, scene_layer, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            const new_entity = try scene_layer.CreateBlankEntity();
            try DeSerializeEntity(reader, new_entity, scene_layer, frame_allocator, engine_allocator);
        }
    }
}

fn DeSerializeUUID(reader: *std.json.Reader, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const parsed_id = try std.json.innerParse(SceneIDComponent, frame_allocator, reader, PraseOptions);
    _ = try scene_layer.AddComponent(SceneIDComponent, parsed_id);
}

fn DeSerializeSceneDataComponent(reader: *std.json.Reader, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, scene_asset_handle: AssetHandle) !void {
    const parsed = try std.json.innerParse(SceneComponent, frame_allocator, reader, PraseOptions);
    const scene_component = try scene_layer.AddComponent(SceneComponent, parsed);
    scene_component.mSceneAssetHandle = scene_asset_handle;
}

fn DeserializeSceneTransform(reader: *std.json.Reader, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const parsed_transform = try std.json.innerParse(SceneTransformComponent, frame_allocator, reader, PraseOptions);
    _ = try scene_layer.AddComponent(SceneTransformComponent, parsed_transform);
}

fn DeSerializeSceneScripts(reader: *std.json.Reader, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(reader);

    var current_id = scene_layer.mSceneID;
    while (current_id != SceneLayer.NullScene) {
        //skip past object field called "component"
        _ = try SkipToken(reader);

        const component_data_token = try reader.next();
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        const new_component_parsed = try std.json.parseFromSlice(SceneScriptComponent, frame_allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        const parsed_script_component = new_component_parsed.value;

        //skip past the object field called "AssetFileData"
        _ = try reader.next();

        //read the next token which will be the potential path of the asset
        const file_data_token = try reader.next();
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

fn DeSerializeEntity(reader: *std.json.Reader, entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    while (true) {
        const token = try reader.nextAlloc(frame_allocator, .alloc_if_needed);
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
            try DeSerializeBasicComponent(reader, entity, CameraComponent, frame_allocator);
            try DeserializeCameraComponent(entity, engine_allocator);
        } else if (std.mem.eql(u8, actual_value, "AISlotComponent")) {
            try DeSerializeBasicComponent(reader, entity, AISlotComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "PlayerSlotComponent")) {
            try DeSerializeBasicComponent(reader, entity, PlayerSlotComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityIDComponent")) {
            try DeSerializeBasicComponent(reader, entity, EntityIDComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityNameComponent")) {
            try DeSerializeBasicComponent(reader, entity, EntityNameComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityScripts")) {
            try DeSerializeEntityScripts(reader, entity, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "QuadComponent")) {
            try DeSerializeBasicComponent(reader, entity, QuadComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "TransformComponent")) {
            try DeSerializeBasicComponent(reader, entity, EntityTransformComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            try DeSerializeParentComponent(reader, entity, scene_layer, frame_allocator, engine_allocator);
        }
    }
}

fn DeSerializeBasicComponent(reader: *std.json.Reader, entity: Entity, comptime component_type: type, frame_allocator: std.mem.Allocator) !void {
    const parsed_component = try std.json.innerParse(component_type, frame_allocator, reader, PraseOptions);
    _ = try entity.AddComponent(component_type, parsed_component);
}

fn DeserializeCameraComponent(entity: Entity, engine_allocator: std.mem.Allocator) !void {
    if (entity.GetComponent(CameraComponent)) |camera_component| {
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
    }
}

fn DeSerializeEntityScripts(reader: *std.json.Reader, entity: Entity, frame_allocator: std.mem.Allocator) !void {
    //skip past begin object token
    _ = try SkipToken(reader);

    var current_id = entity.mEntityID;
    while (current_id != Entity.NullEntity) {
        //skip past object field called "component"
        _ = try SkipToken(reader);

        const component_data_token = try reader.nextAlloc(frame_allocator, .alloc_if_needed);
        const component_data_string = switch (component_data_token) {
            .string => |component_data| component_data,
            .allocated_string => |component_data| component_data,
            else => @panic("should be a string!!\n"),
        };

        const new_component_parsed = try std.json.parseFromSlice(EntityScriptComponent, frame_allocator, component_data_string, .{});
        defer new_component_parsed.deinit();
        const parsed_script_component = new_component_parsed.value;

        //skip past the object field called "AssetFileData"
        _ = try SkipToken(reader);

        //read the next token which will be the potential path of the asset
        const file_data_token = try reader.nextAlloc(frame_allocator, .alloc_if_needed);
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
    _ = try SkipToken(reader);
}

fn DeSerializeParentComponent(reader: *std.json.Reader, entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) anyerror!void {
    if (entity.HasComponent(EntityParentComponent)) {
        try AddToExistingChildren(reader, entity, scene_layer, frame_allocator, engine_allocator);
    } else {
        try MakeEntityParent(reader, entity, scene_layer, frame_allocator, engine_allocator);
    }
}

fn AddToExistingChildren(reader: *std.json.Reader, parent_entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    const new_entity = try scene_layer.CreateBlankEntity();

    const parent_component = parent_entity.GetComponent(EntityParentComponent).?;
    var child_entity = Entity{ .mEntityID = parent_component.mFirstChild, .mECSManagerRef = parent_entity.mECSManagerRef };

    // Find the last child in the list
    var child_component = child_entity.GetComponent(EntityChildComponent).?;
    while (child_component.mNext != Entity.NullEntity) {
        child_entity.mEntityID = child_component.mNext;
        child_component = child_entity.GetComponent(EntityChildComponent).?;
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

    try DeSerializeEntity(reader, new_entity, scene_layer, frame_allocator, engine_allocator);
}

fn MakeEntityParent(reader: *std.json.Reader, parent_entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
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

    try DeSerializeEntity(reader, new_entity, scene_layer, frame_allocator, engine_allocator);
}
