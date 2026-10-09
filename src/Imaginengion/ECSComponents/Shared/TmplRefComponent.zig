const std = @import("std");
const Inspector = @import("../../UI/Inspector.zig");
const EngineContext = @import("../../Core/EngineContext.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const TmplRefComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "TmplRefComponent";
//only Spawn and Make Template give an object its template, an empty one does nothing.
//removing it is fine: the object stops being linked to its template and keeps whatever it has
pub const Addable: bool = false;

/// The template this object is a copy of: an EntityAsset, SceneAsset, PlayerAsset or GCAsset, going by the
/// type of object that holds this. See ECSObject.Core.Fill
mTmpl: AssetHandle = .uninit,

pub fn Deinit(self: *TmplRefComponent, _: *EngineContext) void {
    self.mTmpl.ReleaseAsset();
}

/// The copy releases the handle itself, so it needs its own reference
pub fn Clone(self: *const TmplRefComponent, _: *EngineContext) !TmplRefComponent {
    self.mTmpl.RetainAsset();
    return self.*;
}

/// The template, shown only: opening it to edit is the Components panel's Edit Template button
pub fn UIRender(self: *TmplRefComponent, ui: *Inspector.Builder) !void {
    try ui.Asset(&self.mTmpl, "Template", &.{}, .{});
}

//the handle is saved as the template's path, like any other asset handle
const Json = JsonUtils.JsonFields(TmplRefComponent, .{ .Tmpl = "mTmpl" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
