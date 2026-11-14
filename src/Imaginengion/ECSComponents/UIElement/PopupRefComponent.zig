const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const ObjectLink = @import("../../ECSObjects/ObjectLink.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const RefMap = @import("../../ECSObjects/ECSObject.zig").RefMap;
const Inspector = @import("../../UI/Inspector.zig");

const PopupRefComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "PopupRefComponent";

/// On an entity's UI element (UIElementComponent): the popup it opens, for a script that opens one (the stock OpenPopup
/// and OpenContextMenu scripts, see UI/WidgetActions.zig). Only data: what opening it means is the script's. Saved as the
/// popup's UUID, so the popup needs one
mPopup: Entity = .uninit,
/// The UUID mPopup wants, see ObjectLink
mWantedUUID: ?u64 = null,

pub fn Deinit(_: *PopupRefComponent, _: *EngineContext, _: std.mem.Allocator) void {}

pub fn UIRender(self: *PopupRefComponent, ui: *Inspector.Builder) !void {
    _ = try ui.EntityRef(&self.mPopup, "Popup", .{ .OnChange = OnRefEdited });
}

fn OnRefEdited(component: *anyopaque) void {
    const self: *PopupRefComponent = @ptrCast(@alignCast(component));
    self.mWantedUUID = ObjectLink.WantedNow(self.mPopup, self.mWantedUUID);
}

/// See WorldManager.RelinkRefs
pub fn Relink(self: *PopupRefComponent) void {
    ObjectLink.Relink(&self.mPopup, self.mWantedUUID);
}

/// A copy of an opener in a template points at the copy of the popup the template's pointed at
pub fn RemapRefs(self: *PopupRefComponent, ref_map: *const RefMap) void {
    self.mPopup = ref_map.Get(self.mPopup) orelse .uninit;
}

pub fn jsonStringify(self: *const PopupRefComponent, jw: anytype) !void {
    try jw.beginObject();
    if (ObjectLink.WantedNow(self.mPopup, self.mWantedUUID)) |popup_uuid| {
        try jw.objectField("Popup");
        try jw.write(popup_uuid);
    }
    try jw.endObject();
}

pub fn jsonParse(scratch_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!PopupRefComponent {
    const FileData = struct { Popup: ?u64 = null };
    const file_data = try std.json.innerParse(FileData, scratch_allocator, reader, options);

    const popup_uuid = file_data.Popup orelse return .{};
    //read as part of its entity's UIElementComponent, so the entity is what is being read
    const requester = JsonUtils.EngineContextFromAllocator(scratch_allocator).mSerializer.mCurrDeserialize.requester;
    std.debug.assert(requester == .Entity);
    return .{ .mPopup = ObjectLink.Waiting(Entity, requester.Entity.mManager), .mWantedUUID = popup_uuid };
}
