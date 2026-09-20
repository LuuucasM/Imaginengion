const BuiltinComponentCount = @import("../../ECS/Components.zig").BuiltinComponentCount;
const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../ECSObjects/Entity.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Serializer = @import("../../Serializer/Serializer.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const SpawnPossComponent = @This();

pub const Name: []const u8 = "SpawnPossComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SpawnPossComponent) {
            break :blk i + BuiltinComponentCount;
        }
    }
};

mEntityRef: Entity = .uninit,

pub fn Deinit(_: *SpawnPossComponent, _: *EngineContext) void {
    //deinit stuff
}

pub fn jsonStringify(self: *const SpawnPossComponent, jw: anytype) !void {
    try jw.beginObject();

    //entity references are saved as the entity's UUID and turned back into an entity once it is loaded
    if (self.mEntityRef.IsActive()) {
        try jw.objectField("EntityRef");
        try jw.write(self.mEntityRef.GetUUID());
    }

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!SpawnPossComponent {
    const FileData = struct { EntityRef: ?u64 = null };
    const file_data = try std.json.innerParse(FileData, frame_allocator, reader, options);

    if (file_data.EntityRef) |entity_uuid| {
        const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);
        const serializer = &engine_context.mSerializer;
        std.debug.assert(serializer.mCurrDeserialize.requester == .Scene);
        try serializer.AddResolveReq(engine_context.EngineAllocator(), .{
            .Requester = serializer.mCurrDeserialize.requester,
            .UUID = entity_uuid,
            .Resolve = ResolveEntityRef,
        });
    }

    return SpawnPossComponent{};
}

fn ResolveEntityRef(requester: Serializer.Requester, entity_uuid: u64) bool {
    const scene = requester.Scene;
    const entity = scene.mManager.GetObjectByUUID(Entity, entity_uuid) orelse return false;
    //the component may have been removed since the request was made, nothing left to resolve
    const spawn_poss = scene.GetComponent(SpawnPossComponent) orelse return true;
    spawn_poss.mEntityRef = entity;
    return true;
}
