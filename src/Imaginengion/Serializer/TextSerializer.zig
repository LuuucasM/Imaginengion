const std = @import("std");

const EngineContext = @import("../Core/EngineContext.zig");
const Tracy = @import("../Core/Tracy.zig");

const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");

const EntityComponents = @import("../ECSComponents/EComponents.zig");
const EntitySceneComponent = EntityComponents.EntitySceneComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);
const SceneComponents = @import("../ECSComponents/SComponents.zig");
const ScriptComponent = @import("../ECSComponents/Shared/ScriptComponent.zig");

const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;

const STRINGIFY_OPTIONS: std.json.Stringify.Options = .{ .whitespace = .indent_2 };
const PARSE_OPTIONS: std.json.ParseOptions = .{
    .allocate = .alloc_if_needed,
    .max_value_len = std.json.default_max_value_len,
    .ignore_unknown_fields = true,
};

/// Children and scripts are created blank since all of their components come from the file
const BLANK_ENTITY: Entity.CreateConfig = .{ .bAddUUID = false, .bAddName = false, .bAddTransform = false };

// File layout (the same for scenes and entities, scenes additionally have "Entities"):
// {
//   "<Component.Name>": { component json }, ...
//   "Scripts": [ { ScriptComponent json }, ... ],
//   "Children": [ { entity }, ... ],   (entities only)
//   "Entities": [ { entity }, ... ]    (scenes only, the scene's top level entities)
// }

//==================================SERIALIZING ==================================================
pub fn SerializeECSObject(engine_context: *EngineContext, object: anytype, abs_path: []const u8) !void {
    const zone = Tracy.ZoneInit("TextSerializer::SerializeECSObject(" ++ Tracy.ShortTypeName(@TypeOf(object)) ++ ")", @src());
    defer zone.Deinit();
    zone.Text(abs_path);

    const frame_allocator = engine_context.FrameAllocator();

    var out: std.Io.Writer.Allocating = .init(frame_allocator);
    defer out.deinit();

    var write_stream: std.json.Stringify = .{ .writer = &out.writer, .options = STRINGIFY_OPTIONS };
    try SerializeObject(&write_stream, frame_allocator, object);

    //write the whole file at once so a failed serialize never leaves a half written file behind
    try std.Io.Dir.cwd().writeFile(engine_context.Io(), .{ .sub_path = abs_path, .data = out.written() });
}

fn SerializeObject(write_stream: *std.json.Stringify, frame_allocator: std.mem.Allocator, object: anytype) anyerror!void {
    const obj_t = @TypeOf(object);

    try write_stream.beginObject();

    inline for (comptime SerializeList(obj_t)) |component_type| {
        if (object.GetComponent(component_type)) |component| {
            try write_stream.objectField(component_type.Name);
            try write_stream.write(component);
        }
    }

    //script children only hold their ScriptComponent + a script type tag that AddScript recreates from the asset
    var script_iter = object.GetIterator(.Script);
    if (script_iter.next()) |first_script| {
        try write_stream.objectField("Scripts");
        try write_stream.beginArray();
        try write_stream.write(first_script.GetComponent(ScriptComponent).?);
        while (script_iter.next()) |script| {
            try write_stream.write(script.GetComponent(ScriptComponent).?);
        }
        try write_stream.endArray();
    }

    if (obj_t == Entity) {
        var child_iter = object.GetIterator(.Child);
        if (child_iter.next()) |first_child| {
            try write_stream.objectField("Children");
            try write_stream.beginArray();
            try SerializeObject(write_stream, frame_allocator, first_child);
            while (child_iter.next()) |child| {
                try SerializeObject(write_stream, frame_allocator, child);
            }
            try write_stream.endArray();
        }
    }

    if (obj_t == Scene) {
        try SerializeSceneEntities(write_stream, frame_allocator, object);
    }

    try write_stream.endObject();
}

fn SerializeSceneEntities(write_stream: *std.json.Stringify, frame_allocator: std.mem.Allocator, scene: Scene) !void {
    //only the top level entities, children are written by their parent
    const EntitySceneQuery = GroupQuery{ .Component = EntitySceneComponent };
    const EntityChildQuery = GroupQuery{ .Component = EntityChildComponent };
    const entity_list = try scene.GetEntityGroup(frame_allocator, .{
        .Not = .{
            .mFirst = &EntitySceneQuery,
            .mSecond = &EntityChildQuery,
        },
    });

    if (entity_list.items.len == 0) return;

    try write_stream.objectField("Entities");
    try write_stream.beginArray();
    for (entity_list.items) |entity_id| {
        try SerializeObject(write_stream, frame_allocator, scene.GetEntity(entity_id));
    }
    try write_stream.endArray();
}
//========================================= END SERIALIZING ===============================================

//====================================== DESRIALIZING ========================================================
pub fn DeserializeECSObj(engine_context: *EngineContext, object: anytype, abs_path: []const u8) !void {
    const zone = Tracy.ZoneInit("TextSerializer::DeserializeECSObj(" ++ Tracy.ShortTypeName(@TypeOf(object)) ++ ")", @src());
    defer zone.Deinit();
    zone.Text(abs_path);

    const frame_allocator = engine_context.FrameAllocator();

    const contents = try std.Io.Dir.cwd().readFileAlloc(engine_context.Io(), abs_path, frame_allocator, .unlimited);

    var scanner = std.json.Scanner.initCompleteInput(frame_allocator, contents);
    defer scanner.deinit();

    try DeserializeObject(engine_context, &scanner, object);

    if (.end_of_document != try scanner.next()) return error.UnexpectedToken;
}

fn DeserializeObject(engine_context: *EngineContext, scanner: *std.json.Scanner, object: anytype) anyerror!void {
    const obj_t = @TypeOf(object);

    if (.object_begin != try scanner.next()) return error.UnexpectedToken;

    while (true) {
        const key = switch (try scanner.nextAlloc(engine_context.FrameAllocator(), .alloc_if_needed)) {
            .object_end => return,
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };

        if (try DeserializeComponent(engine_context, scanner, object, key)) continue;

        if (std.mem.eql(u8, key, "Scripts")) {
            try DeserializeScripts(engine_context, scanner, object);
        } else if (obj_t == Entity and std.mem.eql(u8, key, "Children")) {
            try DeserializeEntityList(engine_context, scanner, object);
        } else if (obj_t == Scene and std.mem.eql(u8, key, "Entities")) {
            try DeserializeEntityList(engine_context, scanner, object);
        } else {
            //a component that no longer exists or is no longer serialized, skip it so the rest of the file still loads
            std.log.warn("Skipping unknown key '{s}' while deserializing {s}", .{ key, @typeName(obj_t) });
            try scanner.skipValue();
        }
    }
}

/// Returns false if key is not the name of a serializable component for this object type
fn DeserializeComponent(engine_context: *EngineContext, scanner: *std.json.Scanner, object: anytype, key: []const u8) !bool {
    inline for (comptime SerializeList(@TypeOf(object))) |component_type| {
        if (std.mem.eql(u8, key, component_type.Name)) {
            //components that need to know their owner while parsing (e.g. to request UUID resolves) read it from here
            engine_context.mSerializer.mCurrDeserialize = .{ .requester = .Init(object) };

            //parse first then add, so AddComponent can hook up the manager pointers of the parsed value
            const parsed = try std.json.innerParse(component_type, engine_context.FrameAllocator(), scanner, PARSE_OPTIONS);
            const new_component = try object.AddComponent(engine_context, parsed);
            if (@hasDecl(component_type, "PostParse")) {
                try new_component.PostParse(engine_context, object);
            }
            return true;
        }
    }
    return false;
}

fn DeserializeScripts(engine_context: *EngineContext, scanner: *std.json.Scanner, object: anytype) !void {
    if (.array_begin != try scanner.next()) return error.UnexpectedToken;
    while (try scanner.peekNextTokenType() != .array_end) {
        const script_component = try std.json.innerParse(ScriptComponent, engine_context.FrameAllocator(), scanner, PARSE_OPTIONS);
        if (!script_component.mScriptAssetHandle.IsIDValid()) continue; //the script asset could not be found
        //AddScript creates the script child and its script type tag component from the asset
        try object.AddScript(engine_context, script_component.mScriptAssetHandle);
    }
    _ = try scanner.next();
}

/// Reads an array of entities, creating each one as a child of parent (an Entity) or as a top level entity of parent (a Scene)
fn DeserializeEntityList(engine_context: *EngineContext, scanner: *std.json.Scanner, parent: anytype) !void {
    if (.array_begin != try scanner.next()) return error.UnexpectedToken;
    while (try scanner.peekNextTokenType() != .array_end) {
        const new_entity = if (@TypeOf(parent) == Scene)
            try parent.CreateEntity(engine_context, BLANK_ENTITY)
        else
            try parent.CreateChild(engine_context, .Entity, .{
                .bAddUUID = false,
                .bAddName = false,
                .bAddTransform = false,
            });
        try DeserializeObject(engine_context, scanner, new_entity);
    }
    _ = try scanner.next();
}
//======================================================= END DESERIALIZING ==============================================================

fn SerializeList(comptime obj_t: type) []const type {
    if (obj_t == Entity) {
        return &EntityComponents.SerializeList;
    } else if (obj_t == Scene) {
        return &SceneComponents.SerializeList;
    } else {
        @compileError(std.fmt.comptimePrint("Serializing {s} is not supported yet", .{@typeName(obj_t)}));
    }
}
