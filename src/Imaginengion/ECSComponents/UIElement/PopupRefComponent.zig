const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const Entity = @import("../../ECSObjects/Entity.zig");
const ImguiManager = @import("../../Imgui/Imgui.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const Serializer = @import("../../Serializer/Serializer.zig");
const RefMap = @import("../../ECSObjects/ECSObject.zig").RefMap;
const UIManager = @import("../../UI/UIManager.zig");

const PopupRefComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "PopupRefComponent";

/// On an entity's UI element (UIElementComponent): the popup it opens, for a script that opens one (the stock OpenPopup
/// and OpenContextMenu scripts, see UI/WidgetActions.zig). Only data: what opening it means is the script's. Saved as the
/// popup's UUID, so the popup needs one
mPopup: Entity = .uninit,

pub fn Deinit(_: *PopupRefComponent, _: *EngineContext) void {}

pub fn EditorRender(self: *PopupRefComponent, engine_context: *EngineContext) !void {
    if (try ImguiManager.RenderEntityRef(engine_context, &self.mPopup, "Popup")) |entity| self.mPopup = entity;
}

/// A copy of an opener in a template points at the copy of the popup the template's pointed at
pub fn RemapRefs(self: *PopupRefComponent, ref_map: *const RefMap) void {
    self.mPopup = ref_map.Get(self.mPopup) orelse .uninit;
}

pub fn jsonStringify(self: *const PopupRefComponent, jw: anytype) !void {
    try jw.beginObject();
    //entity references are saved as the entity's UUID and turned back into an entity once it is loaded
    if (self.mPopup.IsActive()) {
        try jw.objectField("Popup");
        try jw.write(self.mPopup.GetUUID());
    }
    try jw.endObject();
}

pub fn jsonParse(frame_allocator: std.mem.Allocator, reader: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(reader.*))!PopupRefComponent {
    const FileData = struct { Popup: ?u64 = null };
    const file_data = try std.json.innerParse(FileData, frame_allocator, reader, options);

    if (file_data.Popup) |popup_uuid| {
        const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);
        const serializer = &engine_context.mSerializer;
        //read as part of its entity's UIElementComponent, so the entity is what is being read
        std.debug.assert(serializer.mCurrDeserialize.requester == .Entity);
        try serializer.AddResolveReq(engine_context.EngineAllocator(), .{
            .Requester = serializer.mCurrDeserialize.requester,
            .UUID = popup_uuid,
            .Resolve = ResolvePopup,
        });
    }
    return .{};
}

fn ResolvePopup(requester: Serializer.Requester, popup_uuid: u64) bool {
    const owner = requester.Entity;
    const popup = owner.mManager.GetObjectByUUID(Entity, popup_uuid) orelse return false;
    //the component may have been removed since the request was made, nothing left to resolve
    const popup_ref = UIManager.GetUIComponent(owner, PopupRefComponent) orelse return true;
    popup_ref.mPopup = popup;
    return true;
}
