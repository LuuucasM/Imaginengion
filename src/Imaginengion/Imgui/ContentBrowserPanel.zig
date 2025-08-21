const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvents = @import("../Events/ImguiEvent.zig");
const ImguiEvent = ImguiEvents.ImguiEvent;
const NewProjectEvent = ImguiEvents.NewProjectEvent;
const OpenProjectEvent = ImguiEvents.OpenProjectEvent;
const AssetManager = @import("../Assets/AssetManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ContentBrowserPanel = @This();
const Assets = @import("../Assets/Assets.zig");
const Texture2D = Assets.Texture2D;
const ScriptAsset = Assets.ScriptAsset;
const ImguiUtils = @import("ImguiUtils.zig");
const NewScriptEvent = @import("../Events/ImguiEvent.zig").NewScriptEvent;
const Tracy = @import("../Core/Tracy.zig");

const MAX_PATH_LEN = 260;

mIsVisible: bool = true,
mDirTextureHandle: AssetHandle,
mPngTextureHandle: AssetHandle,
mBackArrowTextureHandle: AssetHandle,
mSceneTextureHandle: AssetHandle,
mScriptTextureHandle: AssetHandle,
mProjectDirectory: ?std.fs.Dir,
mProjectPath: std.ArrayList(u8) = .{},
mCurrentDirectory: ?std.fs.Dir,
mCurrentPath: std.ArrayList(u8) = .{},
mProjectFile: ?std.fs.File = null,

_EngineAllocator: std.mem.Allocator,

pub fn Init(engine_allocator: std.mem.Allocator) !ContentBrowserPanel {
    return ContentBrowserPanel{
        .mIsVisible = true,
        .mDirTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/foldericon.png", .Eng),
        .mPngTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/pngicon.png", .Eng),
        .mBackArrowTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/backarrowicon.png", .Eng),
        .mSceneTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/sceneicon.png", .Eng),
        .mScriptTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/scripticon.png", .Eng),
        .mProjectDirectory = null,
        .mCurrentDirectory = null,
        .mProjectFile = null,

        ._EngineAllocator = engine_allocator,
    };
}

pub fn Deinit(self: *ContentBrowserPanel) void {
    AssetManager.ReleaseAssetHandleRef(&self.mDirTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mPngTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mBackArrowTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mSceneTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mScriptTextureHandle);
    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }
    self.mProjectPath.deinit(self._EngineAllocator);
    if (self.mCurrentDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }
    self.mCurrentPath.deinit(self._EngineAllocator);
    if (self.mProjectFile) |*file| {
        file.close();
        self.mProjectDirectory = null;
    }
}

pub fn OnImguiRender(self: *ContentBrowserPanel) !void {
    const zone = Tracy.ZoneInit("ContentBrowser OIR", @src());
    defer zone.Deinit();

    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("ContentBrowser", null, 0);
    defer imgui.igEnd();

    if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
        imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        try ImguiUtils.AllScriptPopupMenu();
    }

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

    try RenderBackButton(self, thumbnail_size);

    try RenderDirectoryContents(self, thumbnail_size);
}

pub fn OnImguiEvent(self: *ContentBrowserPanel, event: *ImguiEvent) !void {
    switch (event.*) {
        .ET_TogglePanelEvent => self.OnTogglePanelEvent(),
        .ET_NewProjectEvent => |e| try self.OnNewProjectEvent(e),
        .ET_OpenProjectEvent => |e| try self.OnOpenProjectEvent(e),
        else => @panic("That event has not been implemented yet for ContentBrowserPanel!\n"),
    }
}

fn RenderBackButton(self: *ContentBrowserPanel, thumbnail_size: f32) !void {
    const zone = Tracy.ZoneInit("ContentBrowser RenderBackButton", @src());
    defer zone.Deinit();
    if (std.mem.eql(u8, self.mProjectPath.items, self.mCurrentPath.items) == true) return;

    const back_texture = try self.mBackArrowTextureHandle.GetAsset(Texture2D);
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
        self.mCurrentPath.shrinkAndFree(self._EngineAllocator, last_slash);

        self.mCurrentDirectory.?.close();
        self.mCurrentDirectory = try std.fs.openDirAbsolute(self.mCurrentPath.items, .{ .iterate = true });
    }

    imgui.igTextWrapped("Back");
    imgui.igNextColumn();
}

fn RenderDirectoryContents(self: *ContentBrowserPanel, thumbnail_size: f32) !void {
    const zone = Tracy.ZoneInit("ContentBrowser Render Dir Contents", @src());
    defer zone.Deinit();

    var name_buf: [260]u8 = undefined;

    var new_curr_dir: bool = false;

    var iter = self.mCurrentDirectory.?.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            const texture_asset = try self.mDirTextureHandle.GetAsset(Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texture_asset.GetID(), thumbnail_size);

            if (imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
                _ = try self.mCurrentPath.writer(self._EngineAllocator).write("/");
                _ = try self.mCurrentPath.writer(self._EngineAllocator).write(entry.name);

                new_curr_dir = true;
            }
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) {
            const texture_asset = try self.mPngTextureHandle.GetAsset(Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texture_asset.GetID(), thumbnail_size);

            try self.DragDropSourceBase(entry_name, "PNGLoad");
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".imsc") == true) {
            const texutre_asset = try self.mSceneTextureHandle.GetAsset(Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texutre_asset.GetID(), thumbnail_size);

            try self.DragDropSourceBase(entry_name, "IMSCLoad");
            NextColumn(entry_name);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig") == true) {
            const texutre_asset = try self.mScriptTextureHandle.GetAsset(Texture2D);

            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            try RenderImageButton(entry_name, texutre_asset.GetID(), thumbnail_size);

            try self.DragDropSourceScript(entry_name);
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

pub fn OnNewProjectEvent(self: *ContentBrowserPanel, abs_path: []const u8) !void {
    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }

    if (self.mCurrentDirectory) |*dir| {
        dir.close();
        self.mCurrentDirectory = null;
    }

    self.mProjectPath.clearAndFree(self._EngineAllocator);
    self.mCurrentPath.clearAndFree(self._EngineAllocator);

    self.mProjectDirectory = try std.fs.openDirAbsolute(abs_path, .{});
    self.mCurrentDirectory = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });

    _ = try self.mProjectPath.writer(self._EngineAllocator).write(abs_path);
    _ = try self.mCurrentPath.writer(self._EngineAllocator).write(abs_path);

    self.mProjectFile = try self.mProjectDirectory.?.createFile("NewGame.imprj", .{});
}

pub fn OnOpenProjectEvent(self: *ContentBrowserPanel, abs_path: []const u8) !void {
    const dir_name = std.fs.path.dirname(abs_path).?;

    if (self.mProjectDirectory) |*dir| {
        dir.close();
        self.mProjectDirectory = null;
    }

    if (self.mCurrentDirectory) |*dir| {
        dir.close();
        self.mCurrentDirectory = null;
    }

    self.mProjectPath.clearAndFree(self._EngineAllocator);
    self.mCurrentPath.clearAndFree(self._EngineAllocator);

    self.mProjectDirectory = try std.fs.openDirAbsolute(dir_name, .{});
    self.mCurrentDirectory = try std.fs.openDirAbsolute(dir_name, .{ .iterate = true });

    _ = try self.mProjectPath.writer(self._EngineAllocator).write(dir_name);
    _ = try self.mCurrentPath.writer(self._EngineAllocator).write(dir_name);

    self.mProjectFile = try self.mProjectDirectory.?.openFile("NewGame.imprj", .{});
}

pub fn OnNewScriptEvent(self: *ContentBrowserPanel, new_script_event: NewScriptEvent) !void {
    var buffer: [260 * 3]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const cwd = try std.fs.cwd().realpathAlloc(fba.allocator(), ".");
    switch (new_script_event.mScriptType) {
        .OnInputPressed => {
            const source_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd, "src/Imaginengion/Scripts/GameObject/OnInputPressedTemplate.zig" });
            const dest_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mCurrentPath.items, "NewOnInputPressedScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
        .OnUpdateInput => {
            const source_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd, "src/Imaginengion/Scripts/GameObject/OnUpdateInputTemplate.zig" });
            const dest_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mCurrentPath.items, "NewOnUpdateInputScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
        .OnSceneStart => {
            const source_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd, "src/Imaginengion/Scripts/GameObject/OnUpdateInputTemplate.zig" });
            const dest_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mCurrentPath.items, "NewOnSceneStartScript.zig" });
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

fn DragDropSourceBase(self: ContentBrowserPanel, entry_name: []const u8, payload_type: []const u8) !void {
    const zone = Tracy.ZoneInit("ContentBrowser DragDrop Base", @src());
    defer zone.Deinit();
    if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
        defer imgui.igEndDragDropSource();
        var buffer: [MAX_PATH_LEN * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();

        const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ self.mCurrentPath.items, entry_name });

        const rel_path = AssetManager.GetRelPath(abs_path);

        _ = imgui.igSetDragDropPayload(payload_type.ptr, rel_path.ptr, rel_path.len, 0);
    }
}

fn DragDropSourceScript(self: ContentBrowserPanel, entry_name: []const u8) !void {
    const zone = Tracy.ZoneInit("ContentBrowser DragDrop Script", @src());
    defer zone.Deinit();
    if (imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
        defer imgui.igEndDragDropSource();
        var buffer: [MAX_PATH_LEN * 2]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const allocator = fba.allocator();

        const rel_path = try std.fs.path.join(allocator, &[_][]const u8{ self.mCurrentPath.items[self.mProjectPath.items.len..], entry_name });

        var script_handle = try AssetManager.GetAssetHandleRef(rel_path, .Prj);
        defer AssetManager.ReleaseAssetHandleRef(&script_handle);

        const script_asset = try script_handle.GetAsset(ScriptAsset);
        if (script_asset.mScriptType == .OnInputPressed or script_asset.mScriptType == .OnUpdateInput) {
            _ = imgui.igSetDragDropPayload("GameObjectScriptLoad", rel_path.ptr, rel_path.len, 0);
        } else if (script_asset.mScriptType == .OnSceneStart) {
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
