const std = @import("std");
const SceneLayer = @import("SceneLayer.zig");
const LayerType = @import("Components/SceneComponent.zig").LayerType;
const ECSManagerGameObj = @import("../Scene/SceneManager.zig").ECSManagerGameObj;
const Entity = @import("../GameObjects/Entity.zig");
const LinAlg = @import("../Math/LinAlg.zig");
const Mat4f32 = LinAlg.Mat4f32;

const EntityComponents = @import("../GameObjects/Components.zig");
const CameraComponent = EntityComponents.CameraComponent;
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityTextComponent = EntityComponents.TextComponent;

const FrameBuffer = @import("../FrameBuffers/FrameBuffer.zig");
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const TextureFormat = @import("../FrameBuffers/InternalFrameBuffer.zig").TextureFormat;

const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;

const Renderer = @import("../Renderer/Renderer.zig");

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const SceneParentComponent = @import("../ECS/Components.zig").ParentComponent(SceneLayer.Type);
const SceneChildComponent = @import("../ECS/Components.zig").ChildComponent(SceneLayer.Type);
const SceneNameComponent = SceneComponents.NameComponent;

const GameObjectUtils = @import("../GameObjects/GameObjectUtils.zig");

const Assets = @import("../Assets/Assets.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const FileMetaData = Assets.FileMetaData;
const SceneManager = @import("SceneManager.zig");
const SceneType = SceneManager.SceneType;
const AssetType = @import("../Assets/AssetManager.zig").AssetType;
const SceneAsset = Assets.SceneAsset;
const SceneUtils = @import("../Scene/SceneUtils.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const WriteStream = std.json.Stringify;
const StringifyOptions = std.json.Stringify.Options{ .whitespace = .indent_2 };
const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

pub fn SerializeSceneText(frame_allocator: std.mem.Allocator, scene_layer: SceneLayer, abs_path: []const u8) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

    try SerializeScene(&write_stream, scene_layer, frame_allocator);
    try WriteToFile(abs_path, out.written());
}
pub fn DeSerializeSceneText(engine_context: *EngineContext, scene_layer: SceneLayer, abs_path: []const u8) !void {
    const scene_file = try std.fs.openFileAbsolute(abs_path, .{ .mode = .read_only });

    const scene_contents = try GetSceneContents(engine_context, scene_file);

    var io_reader = std.io.Reader.fixed(scene_contents.items);
    var json_reader = std.json.Reader.init(engine_context.FrameAllocator(), &io_reader);

    try SkipToken(&json_reader); //skip the very first begin object at the top level of the file

    try DeSerializeScene(engine_context, &json_reader, scene_layer);

    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    _ = try scene_component.mScenePath.writer(engine_context.EngineAllocator()).write(engine_context.mAssetManager.GetRelPath(abs_path));
}

pub fn SceneReloadText(engine_context: *EngineContext, scene_layer: SceneLayer, scene_component: *SceneComponent) !void {
    const scene_file = try engine_context.mAssetManager.OpenFile(scene_component.mScenePath.items, .Prj);

    const scene_contents = try GetSceneContents(engine_context, scene_file);

    var io_reader = std.io.Reader.fixed(scene_contents.items);
    var json_reader = std.json.Reader.init(engine_context.FrameAllocator(), &io_reader);

    try SkipToken(&json_reader); //skip the very first begin object at the top level of the file

    try DeSerializeSceneEntities(engine_context, &json_reader, scene_layer);
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

pub fn SerializeEntityText(frame_allocator: std.mem.Allocator, entity: Entity, abs_path: []const u8) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

    try write_stream.beginObject();
    try SerializeEntity(&write_stream, entity);
    try write_stream.endObject();

    try WriteToFile(abs_path, out.written());
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

fn GetSceneContents(engine_context: *EngineContext, scene_file: std.fs.File) !std.ArrayList(u8) {
    const file_size = try scene_file.getEndPos();
    var scene_contents = try std.ArrayList(u8).initCapacity(engine_context.FrameAllocator(), file_size);
    try scene_contents.resize(engine_context.FrameAllocator(), file_size);
    _ = try scene_file.readAll(scene_contents.items);

    return scene_contents;
}

fn SerializeScene(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) anyerror!void {
    try write_stream.beginObject();

    inline for (SceneComponents.SerializeList) |component_type| {
        try SerializeUniqueSceneComponent(write_stream, scene_layer, component_type, component_type.Name);
    }

    try SerializeSceneParentComp(write_stream, scene_layer, frame_allocator);

    try SerializeSceneEntities(write_stream, scene_layer, frame_allocator);

    try write_stream.endObject();
}

fn SerializeUniqueSceneComponent(write_stream: *WriteStream, scene_layer: SceneLayer, comptime component_type: type, field_name: []const u8) !void {
    if (scene_layer.GetComponent(component_type)) |component| {
        try write_stream.objectField(field_name);
        try write_stream.write(component);
    }
}

fn SerializeSceneParentComp(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    if (scene_layer.GetComponent(SceneParentComponent)) |parent_component| {
        if (parent_component.mFirstEntity != Entity.NullEntity) {
            var curr_id = parent_component.mFirstEntity;

            while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
                const child_entity = SceneLayer{ .mSceneID = curr_id, .mECSManagerGORef = scene_layer.mECSManagerGORef, .mECSManagerSCRef = scene_layer.mECSManagerSCRef };

                try write_stream.objectField("ChildEntity");

                try write_stream.beginObject();
                try SerializeScene(write_stream, child_entity, frame_allocator);
                try write_stream.endObject();

                const child_component = child_entity.GetComponent(EntityChildComponent).?;
                curr_id = child_component.mNext;
            }
        }
        if (parent_component.mFirstScript != Entity.NullEntity) {
            var curr_id = parent_component.mFirstScript;

            while (true) : (if (curr_id == parent_component.mFirstScript) break) {
                const script_entity = SceneLayer{ .mSceneID = curr_id, .mECSManagerGORef = scene_layer.mECSManagerGORef, .mECSManagerSCRef = scene_layer.mECSManagerSCRef };

                try write_stream.objectField("ScriptEntity");

                try write_stream.beginObject();
                try SerializeScene(write_stream, script_entity, frame_allocator);
                try write_stream.endObject();

                const child_component = script_entity.GetComponent(EntityChildComponent).?;
                curr_id = child_component.mNext;
            }
        }
    }
}

fn SerializeSceneEntities(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) !void {
    const entity_list = try scene_layer.GetEntityGroup(frame_allocator, .{
        .Not = .{
            .mFirst = .{ .Component = EntitySceneComponent },
            .mSecond = .{ .Component = EntityChildComponent },
        },
    });

    for (entity_list.items) |entity_id| {
        const entity = Entity{ .mEntityID = entity_id, .mECSManagerRef = scene_layer.mECSManagerGORef };

        try write_stream.objectField("Entity");
        try write_stream.beginObject();
        try SerializeEntity(write_stream, entity);
        try write_stream.endObject();
    }
}

fn SerializeEntity(write_stream: *WriteStream, entity: Entity) !void {
    inline for (EntityComponents.SerializeList) |component_type| {
        try SerializeUniqueEntityComponent(write_stream, entity, component_type, component_type.Name);
    }
    try SerializeEntityParentCompo(write_stream, entity);
}

fn SerializeUniqueEntityComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8) !void {
    if (entity.GetComponent(component_type)) |component| {
        try write_stream.objectField(field_name);
        try write_stream.write(component);
    }
}

fn SerializeEntityParentCompo(write_stream: *WriteStream, entity: Entity) anyerror!void {
    if (entity.GetComponent(EntityParentComponent)) |parent_component| {
        if (parent_component.mFirstEntity != Entity.NullEntity) {
            var curr_id = parent_component.mFirstEntity;

            while (true) : (if (curr_id == parent_component.mFirstEntity) break) {
                const child_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

                try write_stream.objectField("ChildEntity");

                try write_stream.beginObject();
                try SerializeEntity(write_stream, child_entity);
                try write_stream.endObject();

                const child_component = child_entity.GetComponent(EntityChildComponent).?;
                curr_id = child_component.mNext;
            }
        }
        if (parent_component.mFirstScript != Entity.NullEntity) {
            var curr_id = parent_component.mFirstScript;

            while (true) : (if (curr_id == parent_component.mFirstScript) break) {
                const script_entity = Entity{ .mEntityID = curr_id, .mECSManagerRef = entity.mECSManagerRef };

                try write_stream.objectField("ScriptEntity");

                try write_stream.beginObject();
                try SerializeEntity(write_stream, script_entity);
                try write_stream.endObject();

                const child_component = script_entity.GetComponent(EntityChildComponent).?;
                curr_id = child_component.mNext;
            }
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

fn DeSerializeScene(engine_context: *EngineContext, reader: *std.json.Reader, scene_layer: SceneLayer) !void {
    const frame_allocator = engine_context.FrameAllocator();
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .end_of_document => break,
            .object_begin => continue,
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try frame_allocator.dupe(u8, token_value);
        defer frame_allocator.free(actual_value);

        inline for (SceneComponents.SerializeList) |component_type| {
            if (std.mem.eql(u8, actual_value, component_type.Name)) {
                try DeSerializeUniqueSceneComp(reader, scene_layer, component_type, frame_allocator);
            }
        }

        if (std.mem.eql(u8, actual_value, "Entity")) {
            const new_entity = try scene_layer.CreateBlankEntity();
            try DeSerializeEntity(engine_context, reader, new_entity, scene_layer);
        }
        if (std.mem.eql(u8, actual_value, "ChildEntity")) {
            const new_scene = try scene_layer.AddBlankChild(.Entity);
            try DeSerializeScene(engine_context, reader, new_scene);
        }
        if (std.mem.eql(u8, actual_value, "ScriptEntity")) {
            const new_scene = try scene_layer.AddBlankChild(.Script);
            try DeSerializeScene(engine_context, reader, new_scene);
        }
    }
}

fn DeSerializeSceneEntities(engine_context: *EngineContext, reader: *std.json.Reader, scene_layer: SceneLayer) !void {
    const frame_allocator = engine_context.FrameAllocator();
    while (true) {
        const token = try reader.next();
        const token_value = try switch (token) {
            .end_of_document => break,
            .object_begin => continue,
            .object_end => break,
            .string => |value| value,
            .number => |value| value,

            else => error.NotExpected,
        };

        const actual_value = try frame_allocator.dupe(u8, token_value);
        defer frame_allocator.free(actual_value);

        if (std.mem.eql(u8, actual_value, "ChildEntity")) {
            const new_entity = try scene_layer.CreateBlankEntity();
            try DeSerializeEntity(engine_context, reader, new_entity, scene_layer);
        }
    }
}

fn DeSerializeUniqueSceneComp(reader: *std.json.Reader, scene_layer: SceneLayer, comptime component_type: type, frame_allocator: std.mem.Allocator) !void {
    const parsed_component = try std.json.innerParse(component_type, frame_allocator, reader, PARSE_OPTIONS);
    _ = try scene_layer.AddComponent(component_type, parsed_component);
}

fn DeSerializeEntity(engine_context: *EngineContext, reader: *std.json.Reader, entity: Entity, scene_layer: SceneLayer) !void {
    const frame_allocator = engine_context.FrameAllocator();

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

        inline for (EntityComponents.SerializeList) |component_type| {
            if (std.mem.eql(u8, actual_value, component_type.Name)) {
                try DeSerializeUniqueComp(engine_context, component_type, reader, entity);
            }
        }

        if (std.mem.eql(u8, actual_value, "ChildEntity")) {
            const new_entity = try scene_layer.AddBlankChildEntity(entity, .Entity);
            try DeSerializeEntity(engine_context, reader, new_entity, scene_layer);
        }
        if (std.mem.eql(u8, actual_value, "ScriptEntity")) {
            const new_script = try scene_layer.AddBlankChildEntity(entity, .Script);
            try DeSerializeEntity(engine_context, reader, new_script, scene_layer);
        }
    }
}

fn DeSerializeUniqueComp(engine_context: *EngineContext, comptime component_type: type, reader: *std.json.Reader, entity: Entity) !void {
    const parsed_component = try std.json.innerParse(component_type, engine_context.FrameAllocator(), reader, PARSE_OPTIONS);
    _ = try entity.AddComponent(component_type, parsed_component);
    if (component_type == CameraComponent) {
        try DeserializeCameraComponent(engine_context, entity);
    }
    if (component_type == EntityTextComponent) {
        try DeserializeTextComponent(engine_context.EngineAllocator(), entity);
    }
    if (component_type == EntityTransformComponent) {
        DeserializeTransformComponent(entity);
    }
    if (component_type == EntityNameComponent) {
        try DeserializeEntityNameComp(engine_context.EngineAllocator(), entity);
    }
}

fn DeserializeCameraComponent(engine_context: *EngineContext, entity: Entity) !void {
    if (entity.GetComponent(CameraComponent)) |camera_component| {
        const ecs_allocator = engine_context.EngineAllocator();
        camera_component.mViewportFrameBuffer = try FrameBuffer.Init(ecs_allocator, &[_]TextureFormat{.RGBA8}, .None, 1, false, camera_component.mViewportWidth, camera_component.mViewportHeight);
        camera_component.mViewportVertexArray = VertexArray.Init();
        camera_component.mViewportVertexBuffer = VertexBuffer.Init(@sizeOf([4][2]f32));
        camera_component.mViewportIndexBuffer = undefined;

        const shader_asset = engine_context.mRenderer.GetSDFShader();
        try camera_component.mViewportVertexBuffer.SetLayout(engine_context.EngineAllocator(), shader_asset.GetLayout());
        camera_component.mViewportVertexBuffer.SetStride(shader_asset.GetStride());

        var index_buffer_data = [6]u32{ 0, 1, 2, 2, 3, 0 };
        camera_component.mViewportIndexBuffer = IndexBuffer.Init(index_buffer_data[0..], 6);

        var data_vertex_buffer = [4][2]f32{ [2]f32{ -1.0, -1.0 }, [2]f32{ 1.0, -1.0 }, [2]f32{ 1.0, 1.0 }, [2]f32{ -1.0, 1.0 } };
        camera_component.mViewportVertexBuffer.SetData(&data_vertex_buffer[0][0], @sizeOf([4][2]f32), 0);
        try camera_component.mViewportVertexArray.AddVertexBuffer(engine_context.EngineAllocator(), camera_component.mViewportVertexBuffer);
        camera_component.mViewportVertexArray.SetIndexBuffer(camera_component.mViewportIndexBuffer);

        camera_component.SetViewportSize(camera_component.mViewportWidth, camera_component.mViewportHeight);
    }
}

fn DeserializeTextComponent(engine_allocator: std.mem.Allocator, entity: Entity) !void {
    if (entity.GetComponent(EntityTextComponent)) |text_component| {
        const new_memory = try engine_allocator.alloc(u8, text_component.mText.items.len);

        @memcpy(new_memory, text_component.mText.items);

        text_component.mText.deinit(engine_allocator);

        text_component.mText.items = new_memory;

        text_component.mText.capacity = new_memory.len;
    }
}

fn DeserializeTransformComponent(entity: Entity) void {
    entity._CalculateWorldTransform();
}

fn DeserializeEntityNameComp(engine_allocator: std.mem.Allocator, entity: Entity) !void {
    if (entity.GetComponent(EntityNameComponent)) |name_component| {
        const new_memory = try engine_allocator.alloc(u8, name_component.mName.items.len);

        @memcpy(new_memory, name_component.mName.items);

        name_component.mName.deinit(name_component.mAllocator);

        name_component.mName.items = new_memory;

        name_component.mName.capacity = new_memory.len;

        name_component.mAllocator = engine_allocator;
    }
}
