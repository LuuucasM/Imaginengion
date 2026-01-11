const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvents = @import("../Events/ImguiEvent.zig");
const ImguiEvent = ImguiEvents.ImguiEvent;
const NewProjectEvent = ImguiEvents.NewProjectEvent;
const OpenProjectEvent = ImguiEvents.OpenProjectEvent;
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ContentBrowserPanel = @This();
const Assets = @import("../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const ScriptAsset = Assets.ScriptAsset;
const ImguiUtils = @import("ImguiUtils.zig");
const NewScriptEvent = @import("../Events/ImguiEvent.zig").NewScriptEvent;
const Tracy = @import("../Core/Tracy.zig");
const SceneComponent = @import("../Scene/SceneComponents.zig").SceneComponent;
const EngineContext = @import("../Core/EngineContext.zig");

const MAX_PATH_LEN = 260;

mIsVisible: bool = true,

mDirTextureHandle: AssetHandle = undefined,
mPngTextureHandle: AssetHandle = undefined,
mBackArrowTextureHandle: AssetHandle = undefined,
mSceneTextureHandle: AssetHandle = undefined,
mScriptTextureHandle: AssetHandle = undefined,
mAudioTextureHandle: AssetHandle = undefined,

mProjectDirectory: ?std.fs.Dir = null,
mProjectPath: std.ArrayList(u8) = .{},
mCurrentDirectory: ?std.fs.Dir = null,
mCurrentPath: std.ArrayList(u8) = .{},
mProjectFile: ?std.fs.File = null,

pub fn Init(self: *ContentBrowserPanel, engine_context: *EngineContext) !void {
    self.mDirTextureHandle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/foldericon.png", .Eng);
    self.mPngTextureHandle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/pngicon.png", .Eng);
    self.mBackArrowTextureHandle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/backarrowicon.png", .Eng);
    self.mSceneTextureHandle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/sceneicon.png", .Eng);
    self.mScriptTextureHandle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/scripticon.png", .Eng);
    self.mAudioTextureHandle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/mp3.png", .Eng);
}

pub fn Deinit(self: *ContentBrowserPanel, engine_context: *EngineContext) void {
    engine_context.mAssetManager.ReleaseAssetHandleRef(&self.mDirTextureHandle);
    engine_context.mAssetManager.ReleaseAssetHandleRef(&self.mPngTextureHandle);
    engine_context.mAssetManager.ReleaseAssetHandleRef(&self.mBackArrowTextureHandle);
    engine_context.mAssetManager.ReleaseAssetHandleRef(&self.mSceneTextureHandle);
    engine_context.mAssetManager.ReleaseAssetHandleRef(&self.mScriptTextureHandle);
    engine_context.mAssetManager.ReleaseAssetHandleRef(&self.mAudioTextureHandle);
    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }
    self.mProjectPath.deinit(engine_context.EngineAllocator());
    if (self.mCurrentDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }
    self.mCurrentPath.deinit(engine_context.EngineAllocator());
    if (self.mProjectFile) |*file| {
        file.close();
        self.mProjectDirectory = null;
    }
}

pub fn OnImguiRender(self: *ContentBrowserPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("ContentBrowser OIR", @src());
    defer zone.Deinit();

    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("ContentBrowser", null, 0);
    defer imgui.igEnd();

    try self.HandlePopupContext(engine_context);

    //if we dont have a project directory yet dont try to print stuff
    if (self.mProjectDirectory == null) return;

    //calculate column stuff
    const padding: f32 = 8.0;
    const thumbnail_size: f32 = 70.0;
    const cell_size: f32 = thumbnail_size + padding;
    var content_region: imgui.struct_ImVec2 = .{};
    imgui.igGetContentRegionAvail(&content_region);
    const panel_width = content_region.x;
    var column_count: i32 = @intFromFloat(panel_width / cell_size);
    if (column_count < 1) {
        column_count = 1;
    }

    imgui.igColumns(column_count, 0, false);
    defer imgui.igColumns(1, 0, true);

    try self.RenderBackButton(engine_context, thumbnail_size);
    try self.RenderDirectoryContents(engine_context, thumbnail_size);
}

pub fn OnImguiEvent(self: *ContentBrowserPanel, engine_allocator: std.mem.Allocator, event: *ImguiEvent) !void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        .ET_NewProjectEvent => |e| try self.OnNewProjectEvent(engine_allocator, e),
        .ET_OpenProjectEvent => |e| try self.OnOpenProjectEvent(engine_allocator, e),
        else => @panic("That event has not been implemented yet for ContentBrowserPanel!\n"),
    }
}

fn HandlePopupContext(_: *ContentBrowserPanel, engine_context: *EngineContext) !void {
    if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
        imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        if (imgui.igMenuItem_Bool("New Scene Layer", "", false, true) == true) {
            try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), .{ .ET_NewSceneEvent = .{ .mLayerType = SceneComponent.LayerType.GameLayer } });
        }
        try ImguiUtils.AllScriptPopupMenu(engine_context);
    }
}

fn RenderBackButton(self: *ContentBrowserPanel, engine_context: *EngineContext, thumbnail_size: f32) !void {
    const zone = Tracy.ZoneInit("ContentBrowser RenderBackButton", @src());
    defer zone.Deinit();

    const engine_allocator = engine_context.EngineAllocator();

    if (std.mem.eql(u8, self.mProjectPath.items, self.mCurrentPath.items) == true) return;

    const back_texture = try self.mBackArrowTextureHandle.GetAsset(engine_context, Texture2D);
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, back_texture.GetID())));
    //imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.7, .y = 0.2, .z = 0.3, .w = 1.0 });
    _ = imgui.igImageButton(
        "back",
        texture_id,
        .{ .x = thumbnail_size, .y = thumbnail_size },
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 1 },
        .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        .{ .x = 1, .y = 1, .z = 1, .w = 1 },
    );
    //imgui.igPopStyleColor(1);

    if (imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
        const last_slash = std.mem.lastIndexOf(u8, self.mCurrentPath.items, "/").?;
        self.mCurrentPath.shrinkAndFree(engine_allocator, last_slash);

        self.mCurrentDirectory.?.close();
        self.mCurrentDirectory = try std.fs.openDirAbsolute(self.mCurrentPath.items, .{ .iterate = true });
    }

    imgui.igTextWrapped("Back");
    imgui.igNextColumn();
}

fn RenderDirectoryContents(self: *ContentBrowserPanel, engine_context: *EngineContext, thumbnail_size: f32) !void {
    const zone = Tracy.ZoneInit("ContentBrowser Render Dir Contents", @src());
    defer zone.Deinit();

    var name_buf: [260]u8 = undefined;

    var new_curr_dir: bool = false;

    var iter = self.mCurrentDirectory.?.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const texture_asset = try self.mDirTextureHandle.GetAsset(engine_context, Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texture_asset.GetID(), thumbnail_size);

            if (imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
                _ = try self.mCurrentPath.writer(engine_context.EngineAllocator()).write("/");
                _ = try self.mCurrentPath.writer(engine_context.EngineAllocator()).write(entry.name);

                new_curr_dir = true;
            }
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) {
            const texture_asset = try self.mPngTextureHandle.GetAsset(engine_context, Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texture_asset.GetID(), thumbnail_size);

            try self.DragDropSourceBase(engine_context, entry_name, "PNGLoad");
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".imsc") == true) {
            const texutre_asset = try self.mSceneTextureHandle.GetAsset(engine_context, Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texutre_asset.GetID(), thumbnail_size);

            try self.DragDropSourceBase(engine_context, entry_name, "IMSCLoad");
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig") == true) {
            const texutre_asset = try self.mScriptTextureHandle.GetAsset(engine_context, Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texutre_asset.GetID(), thumbnail_size);

            try self.DragDropSourceScript(engine_context, entry_name);
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".mp3") == true) {
            const texutre_asset = try self.mAudioTextureHandle.GetAsset(engine_context, Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texutre_asset.GetID(), thumbnail_size);

            try self.DragDropSourceBase(engine_context, entry_name, "MP3Load");
            NextColumn(entry_name);
        }
    }
    if (new_curr_dir) {
        self.mCurrentDirectory.?.close();
        self.mCurrentDirectory = try std.fs.openDirAbsolute(self.mCurrentPath.items, .{ .iterate = true });
    }
}

pub fn OnTogglePanelEvent(self: *ContentBrowserPanel) void {
    self.mIsVisible = !self.mIsVisible;
}

pub fn OnNewProjectEvent(self: *ContentBrowserPanel, engine_allocator: std.mem.Allocator, abs_path: []const u8) !void {
    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }

    if (self.mCurrentDirectory) |*dir| {
        dir.close();
        self.mCurrentDirectory = null;
    }

    self.mProjectPath.clearAndFree(engine_allocator);
    self.mCurrentPath.clearAndFree(engine_allocator);

    self.mProjectDirectory = try std.fs.openDirAbsolute(abs_path, .{});
    self.mCurrentDirectory = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });

    _ = try self.mProjectPath.writer(engine_allocator).write(abs_path);
    _ = try self.mCurrentPath.writer(engine_allocator).write(abs_path);

    self.mProjectFile = try self.mProjectDirectory.?.createFile("NewGame.imprj", .{});
}

pub fn OnOpenProjectEvent(self: *ContentBrowserPanel, engine_allocator: std.mem.Allocator, abs_path: []const u8) !void {
    const dir_name = std.fs.path.dirname(abs_path).?;

    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }

    if (self.mCurrentDirectory) |*dir| {
        dir.close();
        self.mCurrentDirectory = null;
    }

    self.mProjectPath.clearAndFree(engine_allocator);
    self.mCurrentPath.clearAndFree(engine_allocator);

    self.mProjectDirectory = try std.fs.openDirAbsolute(dir_name, .{});
    self.mCurrentDirectory = try std.fs.openDirAbsolute(dir_name, .{ .iterate = true });

    _ = try self.mProjectPath.writer(engine_allocator).write(dir_name);
    _ = try self.mCurrentPath.writer(engine_allocator).write(dir_name);

    self.mProjectFile = try self.mProjectDirectory.?.openFile("NewGame.imprj", .{});
}

pub fn OnNewScriptEvent(self: *ContentBrowserPanel, engine_context: *EngineContext, new_script_event: NewScriptEvent) !void {
    const frame_allocator = engine_context.FrameAllocator();

    switch (new_script_event.mScriptType) {
        .EntityInputPressed => {
            const source_path = try std.fs.path.join(frame_allocator, &[_][]const u8{ engine_context.mAssetManager.mCWDPath.items, "src/Imaginengion/Scripts/GameObject/OnInputPressedTemplate.zig" });
            const dest_path = try std.fs.path.join(frame_allocator, &[_][]const u8{ self.mCurrentPath.items, "NewOnInputPressedScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
        .EntityOnUpdate => {
            const source_path = try std.fs.path.join(frame_allocator, &[_][]const u8{ engine_context.mAssetManager.mCWDPath.items, "src/Imaginengion/Scripts/GameObject/OnUpdateInputTemplate.zig" });
            const dest_path = try std.fs.path.join(frame_allocator, &[_][]const u8{ self.mCurrentPath.items, "NewOnUpdateInputScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
        .SceneSceneStart => {
            const source_path = try std.fs.path.join(frame_allocator, &[_][]const u8{ engine_context.mAssetManager.mCWDPath.items, "src/Imaginengion/Scripts/GameObject/OnUpdateInputTemplate.zig" });
            const dest_path = try std.fs.path.join(frame_allocator, &[_][]const u8{ self.mCurrentPath.items, "NewOnSceneStartScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
    }
}

fn RenderImageButton(entry_name: []const u8, id: c_uint, thumbnail_size: f32) !void {
    const zone = Tracy.ZoneInit("ContentBrowser Render Image Button", @src());
    defer zone.Deinit();
    _ = imgui.igPushID_Str(entry_name.ptr);
    defer imgui.igPopID();

    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, id)));

    _ = imgui.igImageButton(
        entry_name.ptr,
        texture_id,
        .{ .x = thumbnail_size, .y = thumbnail_size },
        .{ .x = 0.0, .y = 0.0 },
        .{ .x = 1.0, .y = 1.0 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
    );
}

fn DragDropSourceBase(self: ContentBrowserPanel, engine_context: *EngineContext, entry_name: []const u8, payload_type: []const u8) !void {
    const zone = Tracy.ZoneInit("ContentBrowser DragDrop Base", @src());
    defer zone.Deinit();
    if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
        defer imgui.igEndDragDropSource();
        var buffer: [MAX_PATH_LEN * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();

        const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ self.mCurrentPath.items, entry_name });

        const rel_path = engine_context.mAssetManager.GetRelPath(abs_path);

        _ = imgui.igSetDragDropPayload(payload_type.ptr, rel_path.ptr, rel_path.len, 0);
    }
}

fn DragDropSourceScript(self: ContentBrowserPanel, engine_context: *EngineContext, entry_name: []const u8) !void {
    const zone = Tracy.ZoneInit("ContentBrowser DragDrop Script", @src());
    defer zone.Deinit();
    if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
        defer imgui.igEndDragDropSource();
        var buffer: [MAX_PATH_LEN * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();

        const rel_path = try std.fs.path.join(allocator, &[_][]const u8{ self.mCurrentPath.items[self.mProjectPath.items.len..], entry_name });

        var script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), rel_path, .Prj);
        defer engine_context.mAssetManager.ReleaseAssetHandleRef(&script_handle);

        const script_asset = try script_handle.GetAsset(engine_context, ScriptAsset);
        if (script_asset.mScriptType == .EntityInputPressed or script_asset.mScriptType == .EntityOnUpdate) {
            _ = imgui.igSetDragDropPayload("GameObjectScriptLoad", rel_path.ptr, rel_path.len, 0);
        } else if (script_asset.mScriptType == .SceneSceneStart) {
            _ = imgui.igSetDragDropPayload("SceneScriptLoad", rel_path.ptr, rel_path.len, 0);
        }
    }
}

fn NextColumn(entry_name: []const u8) void {
    const zone = Tracy.ZoneInit("ContentBrowser NextColumn", @src());
    defer zone.Deinit();
    imgui.igTextWrapped(@ptrCast(entry_name));
    imgui.igNextColumn();
}
