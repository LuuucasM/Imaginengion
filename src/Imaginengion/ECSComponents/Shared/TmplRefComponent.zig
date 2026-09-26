const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const AssetHandle = @import("../../ECSObjects/AssetHandle.zig");
const imgui = @import("../../Core/CImports.zig").imgui;
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

pub fn EditorRender(self: *TmplRefComponent, engine_context: *EngineContext) !void {
    if (self.mTmpl.IsIDValid() and imgui.igButton("Edit Template", .{ .x = 0, .y = 0 })) {
        //the event carries a reference of its own, the editor takes it over (see EditorProgram.OpenTmpl)
        self.mTmpl.RetainAsset();
        try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .EndOfFrame, .{ .OpenTmplEvent = .{ .mTmpl = self.mTmpl } });
    }

    //shown, not edited: which template an object is a copy of is set when it is spawned
    imgui.igTextUnformatted("Template: ", null);
    imgui.igSameLine(0.0, 0.0);
    if (self.mTmpl.IsIDValid()) {
        //the path is not null terminated, so it goes in with its end
        const rel_path = self.mTmpl.GetFileMetaData().mRelPath.items;
        imgui.igTextUnformatted(rel_path.ptr, rel_path.ptr + rel_path.len);
    } else {
        imgui.igTextUnformatted("None", null);
    }
}

//the handle is saved as the template's path, like any other asset handle
const Json = JsonUtils.JsonFields(TmplRefComponent, .{ .Tmpl = "mTmpl" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
