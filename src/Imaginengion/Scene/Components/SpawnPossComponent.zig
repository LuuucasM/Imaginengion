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

mEntity: Entity = .{},

pub fn Deinit(_: *SpawnPossComponent, _: *EngineContext) !void {
    //deinit stuff
}

pub fn jsonStringify(self: *const SpawnPossComponent, jw: anytype) !void {
    try jw.beginObject();

    //serialize entityRef
    if (self.mEntity.IsActive()) {
        const uuid_component = self.mEntity.GetComponent(EntityUUIDComponent).?;
        jw.objectField("EntityRef");
        jw.write(uuid_component.ID);
    }

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!SpawnPossComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    var result: SpawnPossComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        //deserialize spawn poss comp
        if (std.mem.eql(u8, field_name, "EntityRef")) {
            result.mLayerType = try std.json.innerParse(LayerType, frame_allocator, reader, options);
        }
    }

    return result;
}
