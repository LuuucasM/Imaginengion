const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const ObjectLink = @import("../../ECSObjects/ObjectLink.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const RefMap = @import("../../ECSObjects/ECSObject.zig").RefMap;
const SpawnPossComponent = @This();

pub const Name: []const u8 = "SpawnPossComponent";

mEntityRef: Entity = .uninit,
/// The UUID mEntityRef wants, see ObjectLink
mWantedUUID: ?u64 = null,

pub fn UIRender(self: *SpawnPossComponent, ui: *Inspector.Builder) !void {
    _ = try ui.EntityRef(&self.mEntityRef, "Spawns", .{ .OnChange = OnRefEdited });
}

fn OnRefEdited(component: *anyopaque) void {
    const self: *SpawnPossComponent = @ptrCast(@alignCast(component));
    self.mWantedUUID = ObjectLink.WantedNow(self.mEntityRef, self.mWantedUUID);
}

pub fn Deinit(_: *SpawnPossComponent, _: *EngineContext) void {
    //deinit stuff
}

/// See WorldManager.RelinkRefs
pub fn Relink(self: *SpawnPossComponent) void {
    ObjectLink.Relink(&self.mEntityRef, self.mWantedUUID);
}

pub fn jsonStringify(self: *const SpawnPossComponent, jw: anytype) !void {
    try jw.beginObject();

    if (ObjectLink.WantedNow(self.mEntityRef, self.mWantedUUID)) |entity_uuid| {
        try jw.objectField("EntityRef");
        try jw.write(entity_uuid);
    }

    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!SpawnPossComponent {
    const FileData = struct { EntityRef: ?u64 = null };
    const file_data = try std.json.innerParse(FileData, frame_allocator, reader, options);

    const entity_uuid = file_data.EntityRef orelse return .{};
    const requester = JsonUtils.EngineContextFromAllocator(frame_allocator).mSerializer.mCurrDeserialize.requester;
    std.debug.assert(requester == .Scene);
    return .{ .mEntityRef = ObjectLink.Waiting(Entity, requester.Scene.mManager), .mWantedUUID = entity_uuid };
}

/// A copy of a scene points at the copy of the entity its template pointed at (see ECSObject.Core.Fill)
pub fn RemapRefs(self: *SpawnPossComponent, ref_map: *const RefMap) void {
    self.mEntityRef = ref_map.Get(self.mEntityRef) orelse .uninit;
}
