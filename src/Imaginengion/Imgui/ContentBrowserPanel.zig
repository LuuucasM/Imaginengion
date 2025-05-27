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
const ImguiUtils = @import("ImguiUtils.zig");
const NewScriptEvent = @import("../Events/ImguiEvent.zig").NewScriptEvent;

const MAX_PATH_LEN = 260;

mIsVisible: bool = true,
mDirTextureHandle: AssetHandle,
mPngTextureHandle: AssetHandle,
mBackArrowTextureHandle: AssetHandle,
mSceneTextureHandle: AssetHandle,
mScriptTextureHandle: AssetHandle,
mProjectDirectory: std.ArrayList(u8),
mCurrentDirectory: std.ArrayList(u8),
mProjectFile: ?std.fs.File = null,

pub fn Init(engine_allocator: std.mem.Allocator) !ContentBrowserPanel {
    return ContentBrowserPanel{
        .mIsVisible = true,
        .mDirTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/foldericon.png", .Eng),
        .mPngTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/pngicon.png", .Eng),
        .mBackArrowTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/backarrowicon.png", .Eng),
        .mSceneTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/sceneicon.png", .Eng),
        .mScriptTextureHandle = try AssetManager.GetAssetHandleRef("assets/textures/scripticon.png", .Eng),
        .mProjectDirectory = std.ArrayList(u8).init(engine_allocator),
        .mCurrentDirectory = std.ArrayList(u8).init(engine_allocator),
        .mProjectFile = null,
    };
}

pub fn Deinit(self: *ContentBrowserPanel) void {
    AssetManager.ReleaseAssetHandleRef(&self.mDirTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mPngTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mBackArrowTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mSceneTextureHandle);
    AssetManager.ReleaseAssetHandleRef(&self.mScriptTextureHandle);
    self.mProjectDirectory.deinit();
    self.mCurrentDirectory.deinit();
    if (self.mProjectFile != null) {
        self.mProjectFile.?.close();
    }
}

pub fn OnImguiRender(self: *ContentBrowserPanel) !void {
    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("ContentBrowser", null, 0);
    defer imgui.igEnd();

    if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None) == true and imgui.igIsMouseClicked_Bool(imgui.ImGuiMouseButton_Right, false) == true) {
        imgui.igOpenPopup_Str("RightClickPopup", imgui.ImGuiPopupFlags_None);
    }
    if (imgui.igBeginPopup("RightClickPopup", imgui.ImGuiWindowFlags_None) == true) {
        defer imgui.igEndPopup();
        try ImguiUtils.ScriptPopupMenu();
    }

    //if we dont have a project directory yet dont try to print stuff
    if (self.mCurrentDirectory.items.len == 0) return;

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
    if (std.mem.eql(u8, self.mCurrentDirectory.items, self.mProjectDirectory.items) == true) return;

    const back_texture = try self.mBackArrowTextureHandle.GetAsset(Texture2D);
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, back_texture.GetID())));
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.7, .y = 0.2, .z = 0.3, .w = 1.0 });
    _ = imgui.igImageButton("back", texture_id, .{ .x = thumbnail_size, .y = thumbnail_size }, .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 0, .y = 0, .z = 0, .w = 0 }, .{ .x = 1, .y = 1, .z = 1, .w = 1 });
    imgui.igPopStyleColor(1);

    if (imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
        const last_slash = std.mem.lastIndexOf(u8, self.mCurrentDirectory.items, "/").?;
        self.mCurrentDirectory.shrinkAndFree(last_slash);
    }

    imgui.igTextWrapped("Back");
    imgui.igNextColumn();
}

fn RenderDirectoryContents(self: *ContentBrowserPanel, thumbnail_size: f32) !void {
    const dir = try std.fs.openDirAbsolute(self.mCurrentDirectory.items, .{ .iterate = true });

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var icon_ptr: ?*Texture2D = null;
        if (entry.kind == .directory) {
            icon_ptr = try self.mDirTextureHandle.GetAsset(Texture2D);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) {
            icon_ptr = try self.mPngTextureHandle.GetAsset(Texture2D);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".imsc") == true) {
            icon_ptr = try self.mSceneTextureHandle.GetAsset(Texture2D);
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig") == true) {
            icon_ptr = try self.mScriptTextureHandle.GetAsset(Texture2D);
        }
        if (icon_ptr) |texture| {
            var name_buf: [260]u8 = undefined;
            const entry_name = try std.fmt.bufPrintZ(&name_buf, "{s}", .{entry.name});

            _ = imgui.igPushID_Str(entry_name);
            defer imgui.igPopID();

            const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, texture.GetID())));

            _ = imgui.igImageButton(
                entry_name,
                texture_id,
                .{ .x = thumbnail_size, .y = thumbnail_size },
                .{ .x = 0.0, .y = 0.0 },
                .{ .x = 1.0, .y = 1.0 },
                .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
                .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
            );
            if (entry.kind == .file and imgui.igBeginDragDropSource(imgui.ImGuiDragDropFlags_None) == true) {
                defer imgui.igEndDragDropSource();
                var buffer: [MAX_PATH_LEN * 2]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(&buffer);
                const allocator = fba.allocator();
                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ self.mCurrentDirectory.items, entry_name });

                if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".imsc") == true) {
                    _ = imgui.igSetDragDropPayload("IMSCLoad", full_path[self.mProjectDirectory.items.len..].ptr, full_path.len - self.mProjectDirectory.items.len, 0);
                } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) {
                    _ = imgui.igSetDragDropPayload("PNGLoad", full_path[self.mProjectDirectory.items.len..].ptr, full_path.len - self.mProjectDirectory.items.len, 0);
                } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".zig") == true) {
                    _ = imgui.igSetDragDropPayload("ScriptPayload", full_path[self.mProjectDirectory.items.len..].ptr, full_path.len - self.mProjectDirectory.items.len, 0);
                }
            }
            if (entry.kind == .directory and imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
                _ = try self.mCurrentDirectory.writer().write("/");
                _ = try self.mCurrentDirectory.writer().write(entry.name);
            }

            imgui.igTextWrapped(@ptrCast(entry_name));
            imgui.igNextColumn();
        }
    }
}

pub fn OnTogglePanelEvent(self: *ContentBrowserPanel) void {
    self.mIsVisible = !self.mIsVisible;
}

pub fn OnNewProjectEvent(self: *ContentBrowserPanel, path: []const u8) !void {
    if (self.mProjectDirectory.items.len != 0) {
        self.mProjectDirectory.clearAndFree();
        self.mCurrentDirectory.clearAndFree();
    }
    _ = try self.mProjectDirectory.writer().write(path);
    _ = try self.mCurrentDirectory.writer().write(path);

    var buffer: [MAX_PATH_LEN]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const file_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mProjectDirectory.items, "NewGame.imprj" });
    self.mProjectFile = try std.fs.createFileAbsolute(file_path, .{});
}

pub fn OnOpenProjectEvent(self: *ContentBrowserPanel, path: []const u8) !void {
    if (self.mProjectDirectory.items.len != 0) {
        self.mProjectDirectory.clearAndFree();
        self.mCurrentDirectory.clearAndFree();
    }

    const dir = std.fs.path.dirname(path).?;
    _ = try self.mProjectDirectory.writer().write(dir);
    _ = try self.mCurrentDirectory.writer().write(dir);

    self.mProjectFile = try std.fs.openFileAbsolute(path, .{});
}

pub fn OnNewScriptEvent(self: *ContentBrowserPanel, new_script_event: NewScriptEvent) !void {
    var buffer: [260 * 3]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const cwd = try std.fs.cwd().realpathAlloc(fba.allocator(), ".");
    switch (new_script_event.mScriptType) {
        .OnInputPressed => {
            const source_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd, "src/Imaginengion/Scripts/OnInputPressedTemplate.zig" });
            const dest_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mCurrentDirectory.items, "NewOnInputPressedScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
        .OnUpdateInput => {
            const source_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd, "src/Imaginengion/Scripts/OnUpdateInputTemplate.zig" });
            const dest_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mCurrentDirectory.items, "NewOnUpdateInputScript.zig" });
            try std.fs.copyFileAbsolute(source_path, dest_path, .{});
        },
    }
}
