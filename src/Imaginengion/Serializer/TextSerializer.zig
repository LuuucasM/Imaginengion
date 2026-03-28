const std = @import("std");

const SceneComponents = @import("../Scene/SceneComponents.zig");
const SceneComponent = SceneComponents.SceneComponent;
const SceneScriptComponent = SceneComponents.ScriptComponent;
const SceneParentComponent = @import("../ECS/Components.zig").ParentComponent(SceneLayer.Type);
const SceneChildComponent = @import("../ECS/Components.zig").ChildComponent(SceneLayer.Type);
const SceneNameComponent = SceneComponents.NameComponent;
const SceneUUIDComponent = SceneComponents.UUIDComponent;

const EntityComponents = @import("../GameObjects/Components.zig");
const EntityNameComponent = EntityComponents.NameComponent;
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityTransformComponent = EntityComponents.TransformComponent;
const EntityParentComponent = @import("../ECS/Components.zig").ParentComponent(Entity.Type);
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const EntityTextComponent = EntityComponents.TextComponent;
const EntityUUIDComponent = EntityComponents.UUIDComponent;

const Entity = @import("../GameObjects/Entity.zig");
const SceneLayer = @import("../Scene/SceneLayer.zig");
const EngineContext = @import("../Core/EngineContext.zig");

const WriteStream = std.json.Stringify;
const StringifyOptions = std.json.Stringify.Options{ .whitespace = .indent_2 };
const PARSE_OPTIONS = std.json.ParseOptions{ .allocate = .alloc_if_needed, .max_value_len = std.json.default_max_value_len };

const TextSerializer = @This();
//==================================SERIALIZING ==================================================
pub fn SerializeScene(frame_allocator: std.mem.Allocator, scene_layer: SceneLayer, abs_path: []const u8) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

    try SerializeSceneLayer(&write_stream, scene_layer, frame_allocator);
    try WriteToFile(abs_path, out.written());
}

fn SerializeSceneLayer(write_stream: *WriteStream, scene_layer: SceneLayer, frame_allocator: std.mem.Allocator) anyerror!void {
    try write_stream.beginObject();

    inline for (SceneComponents.SerializeList) |component_type| {
        try SerializeSceneComponent(write_stream, scene_layer, component_type, component_type.Name);
    }

    try SerializeSceneParentComp(write_stream, scene_layer, frame_allocator);

    try SerializeSceneEntities(write_stream, scene_layer, frame_allocator);

    try write_stream.endObject();
}

fn SerializeSceneComponent(write_stream: *WriteStream, scene_layer: SceneLayer, comptime component_type: type, field_name: []const u8) !void {
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
        if (parent_component.mFirstScript != SceneLayer.NullScene) {
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

fn SerializeSceneEntity(write_stream: *WriteStream, entity: Entity) !void {
    inline for (EntityComponents.SerializeList) |component_type| {
        try SerializeEntityComponent(write_stream, entity, component_type, component_type.Name);
    }
    try SerializeEntityParentCompo(write_stream, entity);
}

fn SerializeEntityComponent(write_stream: *WriteStream, entity: Entity, comptime component_type: type, field_name: []const u8) !void {
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

pub fn SerializeEntity(frame_allocator: std.mem.Allocator, entity: Entity, abs_path: []const u8) !void {
    var out: std.io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = StringifyOptions };

    try write_stream.beginObject();
    try SerializeSceneEntity(&write_stream, entity);
    try write_stream.endObject();

    try WriteToFile(abs_path, out.written());
}
//========================================= END SERIALIZING ===============================================

//====================================== DESRIALIZING ========================================================
pub fn DeSerializeScene(engine_context: *EngineContext, scene_layer: SceneLayer, abs_path: []const u8) !void {
    const scene_file = try std.fs.openFileAbsolute(abs_path, .{ .mode = .read_only });

    const scene_contents = try GetSceneContents(engine_context, scene_file);

    var io_reader = std.io.Reader.fixed(scene_contents.items);
    var json_reader = std.json.Reader.init(engine_context.FrameAllocator(), &io_reader);

    try SkipToken(&json_reader); //skip the very first begin object at the top level of the file

    try DeSerializeSceneLayer(engine_context, &json_reader, scene_layer);

    const scene_component = scene_layer.GetComponent(SceneComponent).?;
    _ = try scene_component.mScenePath.writer(engine_context.EngineAllocator()).write(engine_context.mAssetManager.GetRelPath(abs_path));
}

fn GetSceneContents(engine_context: *EngineContext, scene_file: std.fs.File) !std.ArrayList(u8) {
    const file_size = try scene_file.getEndPos();
    var scene_contents = try std.ArrayList(u8).initCapacity(engine_context.FrameAllocator(), file_size);
    try scene_contents.resize(engine_context.FrameAllocator(), file_size);
    _ = try scene_file.readAll(scene_contents.items);

    return scene_contents;
}

fn DeSerializeSceneLayer(engine_context: *EngineContext, reader: *std.json.Reader, scene_layer: SceneLayer) !void {
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
                try DeSerializeSceneComp(engine_context, component_type, reader, scene_layer);
            }
        }

        if (std.mem.eql(u8, actual_value, "Entity")) {
            const new_entity = try scene_layer.CreateEntity(engine_context.EngineAllocator(), .{ .bAddName = false, .bAddTransform = false, .bAddUUID = false });
            try DeserializeThisEntity(engine_context, reader, new_entity, scene_layer);
        }
        if (std.mem.eql(u8, actual_value, "ChildEntity")) {
            const new_scene = try scene_layer.AddChild(engine_context.EngineAllocator(), .Entity, .{ .bAddSceneName = false, .bAddSceneUUID = false });
            try DeSerializeScene(engine_context, reader, new_scene);
        }
        if (std.mem.eql(u8, actual_value, "ScriptEntity")) {
            const new_scene = try scene_layer.AddChild(engine_context.EngineAllocator(), .Script, .{ .bAddSceneName = false, .bAddSceneUUID = false });
            try DeSerializeScene(engine_context, reader, new_scene);
        }
    }
}

fn DeSerializeSceneComp(engine_context: *EngineContext, comptime component_type: type, reader: *std.json.Reader, scene_layer: SceneLayer) !void {
    const new_component = try scene_layer.AddComponent(component_type{});
    engine_context.mSerializer.mCurrDeserialize = .{ .requester = .{ .Scene = scene_layer }, .component_ptr = new_component };
    new_component.* = try std.json.innerParse(component_type, engine_context.FrameAllocator(), reader, PARSE_OPTIONS);
}

fn DeserializeThisEntity(engine_context: *EngineContext, reader: *std.json.Reader, entity: Entity, scene_layer: SceneLayer) !void {
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
                try DeserializeEntityComponent(engine_context, component_type, reader, entity);
            }
        }

        if (std.mem.eql(u8, actual_value, "ChildEntity")) {
            const new_entity = try entity.CreateChild(engine_context.EngineAllocator(), .Entity, .{});
            try DeserializeThisEntity(engine_context, reader, new_entity, scene_layer);
        }
        if (std.mem.eql(u8, actual_value, "ScriptEntity")) {
            const new_script = try entity.CreateChild(engine_context.EngineAllocator(), .Script, .{ .bAddUUID = false, .bAddName = false, .bAddTransform = false });
            try DeserializeThisEntity(engine_context, reader, new_script, scene_layer);
        }
    }
}

fn DeserializeEntityComponent(engine_context: *EngineContext, comptime component_type: type, reader: *std.json.Reader, entity: Entity) !void {
    const new_component = try entity.AddComponent(component_type{});
    engine_context.mSerializer.mCurrDeserialize = .{ .requester = .{ .Entity = entity }, .component_ptr = new_component };
    new_component.* = try std.json.innerParse(component_type, engine_context.FrameAllocator(), reader, PARSE_OPTIONS);
    if (@hasDecl(component_type, "PostParse")) {
        new_component.PostParse(entity);
    }
}

//note: this function is for deserializing prefabs, not to be confused with DeserializeThisEntity which actually deserializes an entity
pub fn DeserializeEntity(scene_layer: SceneLayer, abs_path: []const u8, frame_allocator: std.mem.Allocator) !void {
    const file = try std.fs.openFileAbsolute(abs_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();

    const file_contents = try std.ArrayList(u8).initCapacity(frame_allocator, file_size);
    file.readAll(file_contents.items);

    var io_reader = std.io.Reader.fixed(file_contents.items);

    var reader = std.json.Reader.init(frame_allocator, &io_reader);
    defer reader.deinit();

    const new_entity = try scene_layer.CreateBlankEntity();
    try DeserializeThisEntity(&reader, new_entity, scene_layer, frame_allocator);
}

//======================================================= END DESERIALIZING ==============================================================

fn SkipToken(reader: *std.json.Reader) !void {
    _ = try reader.next();
}
