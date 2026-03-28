const std = @import("std");
const ComponentsList = @import("../Components.zig").ComponentsList;
const UUIDComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

//IMGUI
const imgui = @import("../../Core/CImports.zig").imgui;

pub const Editable: bool = true;
pub const Name: []const u8 = "UUIDComponent";
pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == UUIDComponent) {
            break :blk i + 3; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

ID: u64 = std.math.maxInt(u64),

pub fn Deinit(_: *UUIDComponent, _: *EngineContext) !void {}

pub fn EditorRender(self: *UUIDComponent, _: *EngineContext) !void {
    var buff: [140]u8 = undefined;
    const text = try std.fmt.bufPrintZ(&buff, "{d}\n", .{self.ID});
    _ = imgui.igInputText("ID", text.ptr, text.len, imgui.ImGuiInputTextFlags_ReadOnly, null, null);
}

pub fn jsonStringify(self: *const UUIDComponent, jw: anytype) !void {
    try jw.beginObject();

    jw.objectField("UUID");
    jw.write(self.ID);

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!UUIDComponent {
    if (.object_begin != try reader.next()) return error.UnexpectedToken;

    const engine_context: *EngineContext = @ptrCast(@alignCast(frame_allocator.ptr));

    var result: UUIDComponent = .{};

    while (true) {
        const token = try reader.next();

        const field_name = switch (token) {
            .object_end => break,
            .string => |v| v,
            else => return error.UnexpectedToken,
        };

        //deserialize UUID
        if (std.mem.eql(u8, field_name, "UUID")) {
            const entity_uuid = try std.json.innerParse(u64, frame_allocator, reader, options);
            std.debug.assert(engine_context.mSerializer.mCurrDeserialize.requester == .Entity);
            const entity = engine_context.mSerializer.mCurrDeserialize.requester.Entity;
            entity.mSceneManager.AddUUID(engine_context.EngineAllocator(), entity_uuid, entity.mEntityID);
            result.ID = entity_uuid;
        }
    }

    return result;
}
