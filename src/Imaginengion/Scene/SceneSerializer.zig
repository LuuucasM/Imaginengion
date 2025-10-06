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
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

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
const ParseOptions = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

pub fn SerializeSceneText(scene_layer: SceneLayer, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

    try SerializeSceneData(&write_stream, scene_layer, frame_allocator);
    try WriteToFile(abs_path, out.written());
}

pub fn DeSerializeSceneText(scene_layer: SceneLayer, scene_asset_handle: AssetHandle, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
    const scene_asset = try scene_asset_handle.GetAsset(SceneAsset);

    var io_reader = std.io.Reader.fixed(scene_asset.mSceneContents.items);
    var json_reader = std.json.Reader.init(frame_allocator, &io_reader);
    defer json_reader.deinit();

    try DeSerializeSceneData(&json_reader, scene_layer, frame_allocator, engine_allocator);
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

    try SerializeUniqueSceneComponent(write_stream, scene_layer, SceneIDComponent, "SceneID");
    try SerializeUniqueSceneComponent(write_stream, scene_layer, SceneIDComponent, "SceneData");
    try SerializeUniqueSceneComponent(write_stream, scene_layer, SceneIDComponent, "Transform");
    try SerializeMultiSceneComponents(write_stream, scene_layer, SceneScriptComponent, "SceneScript");

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

fn SerializeUniqueSceneComponent(write_stream: *WriteStream, scene_layer: SceneLayer, comptime component_type: type, field_name: []const u8) !void {
    if (scene_layer.GetComponent(component_type)) |component| {
        try write_stream.objectField(field_name);
        try write_stream.write(component);
    }
}

fn SerializeMultiSceneComponents(write_stream: *WriteStream, scene_layer: SceneLayer, comptime component_type: type, field_name: []const u8) !void {
    if (scene_layer.GetComponent(component_type)) |parent_multi_component| {
        const ecs = scene_layer.mECSManagerSCRef;
        var curr_id = parent_multi_component.mFirst;

        while (true) : (if (curr_id == parent_multi_component.mFirst) break) {
            const component_component = ecs.GetComponent(component_type, curr_id).?;

            try write_stream.objectField(field_name);
            try write_stream.write(component_component);

            curr_id = component_component.mNext;
        }

        try write_stream.endObject();
    }
}

fn SerializeSceneEntities(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const entity_list = try scene_layer.GetEntityGroup(.{
        .Not = .{
            .mFirst = .{ .Component = EntitySceneComponent },
            .mSecond = .{ .Component = EntityChildComponent },
        },
    }, frame_allocator);

    for (entity_list.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerGORef };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try SerializeEntity(write_stream, entity);
        try write_stream.endObject();
    }
}

fn SerializeEntity(write_stream: *WriteStream, entity: Entity) !void {
    try SerializeUniqueEntityComponent(write_stream, entity, CameraComponent, "CameraComponent");
    try SerializeUniqueEntityComponent(write_stream, entity, AISlotComponent, "AISlotComponent");
    try SerializeUniqueEntityComponent(write_stream, entity, PlayerSlotComponent, "PlayerSlotComponent");
    try SerializeUniqueEntityComponent(write_stream, entity, EntityIDComponent, "EntityIDComponent");
    try SerializeUniqueEntityComponent(write_stream, entity, EntityNameComponent, "EntityNameComponent");
    try SerializeUniqueEntityComponent(write_stream, entity, EntityTransformComponent, "TransformComponent");
    try SerializeUniqueEntityComponent(write_stream, entity, QuadComponent, "QuadComponent");
    try SerializeMultiEntityComponents(write_stream, entity, EntityScriptComponent, "EntityScript");

    try SerializeParentComponent(write_stream, entity);
}

fn SerializeUniqueEntityComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8) !void {
    if (entity.GetComponent(component_type)) |component| {
        try write_stream.objectField(field_name);
        try write_stream.write(component);
    }
}

fn SerializeMultiEntityComponents(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8) !void {
    if (entity.GetComponent(component_type)) |parent_multi_component| {
        const ecs = entity.mECSManagerRef;
        var curr_id = parent_multi_component.mFirst;

        while (true) : (if (curr_id == parent_multi_component.mFirst) break) {
            const component_component = ecs.GetComponent(component_type, curr_id).?;

            try write_stream.objectField(field_name);
            try write_stream.write(component_component);

            curr_id = component_component.mNext;
        }

        try write_stream.endObject();
    }
}

fn SerializeParentComponent(write_stream: *WriteStream, entity: Entity) anyerror!void {
    if (entity.GetComponent(EntityParentComponent)) |parent_component| {
        var curr_id = parent_component.mFirstChild;

        while (true) : (if (curr_id == parent_component.mFirstChild) break) {
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

fn WriteToFile(abs_path: []const u8, data: []const u8) !void {
    const file = try std.fs.createFileAbsolute(abs_path, .{ .read = false, .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}

fn DeSerializeSceneData(reader: *std.json.Reader, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) !void {
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
            try DeSerializeSceneComponent(reader, scene_layer, SceneIDComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "SceneData")) {
            try DeSerializeSceneComponent(reader, scene_layer, SceneComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Transform")) {
            try DeSerializeSceneComponent(reader, scene_layer, SceneTransformComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "SceneScript")) {
            try DeSerializeSceneComponent(reader, scene_layer, SceneScriptComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            const new_entity = try scene_layer.CreateBlankEntity();
            try DeSerializeEntity(reader, new_entity, scene_layer, frame_allocator, engine_allocator);
        }
    }
}

fn DeSerializeSceneComponent(reader: *std.json.Reader, scene_layer: SceneLayer, comptime component_type: type, frame_allocator: std.mem.Allocator) !void {
    const parsed_component = try std.json.innerParse(component_type, frame_allocator, reader, ParseOptions);
    _ = try scene_layer.AddComponent(component_type, parsed_component);
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
            try DeSerializeEntityComponent(reader, entity, CameraComponent, frame_allocator);
            try DeserializeCameraComponent(entity, engine_allocator);
        } else if (std.mem.eql(u8, actual_value, "AISlotComponent")) {
            try DeSerializeEntityComponent(reader, entity, AISlotComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "PlayerSlotComponent")) {
            try DeSerializeEntityComponent(reader, entity, PlayerSlotComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityIDComponent")) {
            try DeSerializeEntityComponent(reader, entity, EntityIDComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityNameComponent")) {
            try DeSerializeEntityComponent(reader, entity, EntityNameComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "EntityScript")) {
            try DeSerializeEntityComponent(reader, entity, EntityScriptComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "QuadComponent")) {
            try DeSerializeEntityComponent(reader, entity, QuadComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "TransformComponent")) {
            try DeSerializeEntityComponent(reader, entity, EntityTransformComponent, frame_allocator);
        } else if (std.mem.eql(u8, actual_value, "Entity")) {
            try DeSerializeParentComponent(reader, entity, scene_layer, frame_allocator, engine_allocator);
        }
    }
}

fn DeSerializeEntityComponent(reader: *std.json.Reader, entity: Entity, comptime component_type: type, frame_allocator: std.mem.Allocator) !void {
    const parsed_component = try std.json.innerParse(component_type, frame_allocator, reader, ParseOptions);
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

fn DeSerializeParentComponent(reader: *std.json.Reader, entity: Entity, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator, engine_allocator: std.mem.Allocator) anyerror!void {
    const new_entity = try scene_layer.AddChildEntity(entity);
    try DeSerializeEntity(reader, new_entity, scene_layer, frame_allocator, engine_allocator);
}
