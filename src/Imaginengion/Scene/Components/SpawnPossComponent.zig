const std = @import("std");
const ComponentsList = @import("../SceneComponents.zig").ComponentsList;
const Entity = @import("../../GameObjects/Entity.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const EntityComponents = @import("../../GameObjects/Components.zig");
const EntityUUIDComponent = EntityComponents.UUIDComponent;
const SpawnPossComponent = @This();

pub const Name: []const u8 = "SpawnPossComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == SpawnPossComponent) {
            break :blk i + 3; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

mEntityRef: Entity = .{},

pub fn Deinit(_: *SpawnPossComponent, _: *EngineContext) !void {
    //deinit stuff
}

pub fn jsonStringify(self: *const SpawnPossComponent, jw: anytype) !void {
    try jw.beginObject();

    //serialize entityRef
    if (self.mEntityRef.IsActive()) {
        const uuid_component = self.mEntityRef.GetComponent(EntityUUIDComponent).?;
        try jw.objectField("EntityRef");
        try jw.write(uuid_component.ID);
    }

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!SpawnPossComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        //deserialize spawn poss comp
        if (std.mem.eql(u8, field_name, "EntityRef")) {
            const entity_uuid = try std.json.innerParse(u64, frame_allocator, reader, options);
            std.debug.assert(engine_context.mSerializer.mCurrDeserialize.requester == .Scene);
            const scene_layer = engine_context.mSerializer.mCurrDeserialize.requester.Scene;
            const component_ptr: *SpawnPossComponent = @ptrCast(@alignCast(engine_context.mSerializer.mCurrDeserialize.component_ptr));
            scene_layer.mSceneManager.AddResolveUUID(engine_context.EngineAllocator(), .{ .Requester = .{ .Scene = scene_layer }, .UUID = entity_uuid, .SetLoc = &component_ptr.mEntityRef }) catch @panic("this failed");
        }
    }

    return SpawnPossComponent{};
}
