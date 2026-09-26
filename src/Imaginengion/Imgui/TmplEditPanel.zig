//! A window for editing one template: its tree on the left, the selected object's components on the right, a Save
//! button, and an X that saves and closes. The template is loaded from its file into EngineContext.mTmplEditWorld,
//! where nothing runs, and written back to the same file. The editor keeps one of these per open template.
const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const AssetHandle = @import("../ECSObjects/AssetHandle.zig");
const Entity = @import("../ECSObjects/Entity.zig");
const Scene = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameContext = @import("../ECSObjects/GameContext.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const Serializer = @import("../Serializer/Serializer.zig");
const TextSerializer = @import("../Serializer/TextSerializer.zig");
const ECSDisplay = @import("ECSDisplay.zig");
const ComponentsPanel = @import("ComponentsPanel.zig");
const GroupQuery = @import("../ECS/ECSManager.zig").GroupQuery;
const EntitySceneComponent = @import("../ECSComponents/EComponents.zig").EntitySceneComponent;
const EntityChildComponent = @import("../ECS/Components.zig").ChildComponent(Entity.Type);

const TmplEditPanel = @This();

/// The template being edited, with a reference of its own
mTmpl: AssetHandle,
/// The template's root, loaded from its file into EngineContext.mTmplEditWorld
mRoot: SelectedObject,
/// What the component list shows, separate from the editor's own selection
mSelected: ?SelectedObject,
/// Cleared by the window's X, after which the editor closes it (see Close)
mIsOpen: bool = true,

/// Loads the template's file into the template editing world, with the root selected. Takes over the caller's
/// reference on tmpl
pub fn Open(engine_context: *EngineContext, tmpl: AssetHandle) !TmplEditPanel {
    const rel_path = tmpl.GetFileMetaData().mRelPath.items;
    const kind = Serializer.ObjectKindOf(std.fs.path.extension(rel_path)) orelse return error.NotATmplFile;
    const root: SelectedObject = switch (kind) {
        .Entity => .{ .entity = try Load(Entity, engine_context, tmpl) },
        .Scene => .{ .scene_layer = try Load(Scene, engine_context, tmpl) },
        .Player => .{ .player = try Load(Player, engine_context, tmpl) },
        .GameContext => .{ .gamecontext = try Load(GameContext, engine_context, tmpl) },
    };
    return .{ .mTmpl = tmpl, .mRoot = root, .mSelected = root };
}

/// Writes the template back to its file. The asset manager then notices the file changed and reloads its copy, so the
/// next Spawn uses the edited template
pub fn Save(self: TmplEditPanel, engine_context: *EngineContext) !void {
    const abs_path = try AbsPath(engine_context, self.mTmpl);
    switch (self.mRoot) {
        inline else => |root| try TextSerializer.SerializeECSObject(engine_context, root, abs_path),
    }
}

/// Saves, then takes the template out of the editing world (at the end of the frame) and lets go of the handle.
/// If the save fails nothing else happens, so the edits are still there to try again
pub fn Close(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    try self.Save(engine_context);
    switch (self.mRoot) {
        inline else => |root| try root.Delete(engine_context),
    }
    self.mTmpl.ReleaseAsset();
}

pub fn IsTmpl(self: TmplEditPanel, tmpl: AssetHandle) bool {
    return self.mTmpl.mID == tmpl.mID;
}

/// The file name to show, and the template's asset id after ### so each template gets its own window and dock slot
pub fn WindowName(self: TmplEditPanel, engine_context: *EngineContext) ![:0]const u8 {
    const file_name = std.fs.path.basename(self.mTmpl.GetFileMetaData().mRelPath.items);
    return try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Template - {s}###Tmpl{d}", .{ file_name, self.mTmpl.mID }, 0);
}

pub fn OnImguiRender(self: *TmplEditPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("TmplEditPanel::OnImguiRender", @src());
    defer zone.Deinit();

    const window_name = try self.WindowName(engine_context);
    const is_visible = imgui.igBegin(window_name.ptr, &self.mIsOpen, 0);
    defer imgui.igEnd();
    if (!is_visible) return;

    if (imgui.igButton("Save", .{ .x = 0, .y = 0 })) {
        try self.Save(engine_context);
    }

    //a delete from the tree below only goes through at the end of the frame, so the selection is gone by the next one
    if (self.mSelected) |selected| {
        const is_active = switch (selected) {
            inline else => |object| object.IsActive(),
        };
        if (!is_active) self.mSelected = null;
    }

    const available = imgui.igGetContentRegionAvail();
    if (imgui.igBeginChild_Str("Hierarchy", .{ .x = available.x * 0.4, .y = 0 }, imgui.ImGuiChildFlags_Borders | imgui.ImGuiChildFlags_ResizeX, 0)) {
        switch (self.mRoot) {
            inline else => |root| try self.RenderTree(engine_context, root),
        }
    }
    imgui.igEndChild();

    imgui.igSameLine(0.0, -1.0);

    if (imgui.igBeginChild_Str("Components", .{ .x = 0, .y = 0 }, imgui.ImGuiChildFlags_Borders, 0)) {
        if (self.mSelected) |selected| {
            switch (selected) {
                inline else => |object| try ComponentsPanel.RenderComponents(@TypeOf(object), engine_context, object),
            }
        }
    }
    imgui.igEndChild();
}

/// The root and everything under it, then for a scene its entities
fn RenderTree(self: *TmplEditPanel, engine_context: *EngineContext, root: anytype) !void {
    try ECSDisplay.RenderObject(@TypeOf(root), engine_context, root, .{ .mSelection = &self.mSelected, .mIsRoot = true });

    if (@TypeOf(root) == Scene) {
        imgui.igSeparatorText("Entities");
        //only the top level ones, each draws its own children
        const EntitySceneQuery = GroupQuery{ .Component = EntitySceneComponent };
        const EntityChildQuery = GroupQuery{ .Component = EntityChildComponent };
        const root_entities = try root.GetEntityGroup(engine_context.FrameAllocator(), .{
            .Not = .{
                .mFirst = &EntitySceneQuery,
                .mSecond = &EntityChildQuery,
            },
        });
        for (root_entities.items) |entity_id| {
            try ECSDisplay.RenderObject(Entity, engine_context, root.GetEntity(entity_id), .{ .mSelection = &self.mSelected });
        }
    }
}

/// A blank object in the template editing world, filled from the template's file
fn Load(comptime obj_t: type, engine_context: *EngineContext, tmpl: AssetHandle) !obj_t {
    const object = if (obj_t == Entity)
        try engine_context.mTmplEditScene.CreateEntity(engine_context, Entity.BlankConfig)
    else
        try engine_context.mTmplEditWorld.CreateBlank(obj_t, engine_context);
    errdefer object.Delete(engine_context) catch {};

    //TextSerializer rather than Serializer.DeserializeECSObj: the panel saves to the template's own path, so there is
    //no use recording the file against the object's UUID in mFileObjects
    try TextSerializer.DeserializeECSObj(engine_context, object, try AbsPath(engine_context, tmpl));
    engine_context.mSerializer.ResolveUUIDs();
    return object;
}

fn AbsPath(engine_context: *EngineContext, tmpl: AssetHandle) ![]const u8 {
    const file_data = tmpl.GetFileMetaData();
    return try engine_context.mAssetManager.GetAbsPath(engine_context.FrameAllocator(), file_data.mRelPath.items, file_data.mPathType);
}
