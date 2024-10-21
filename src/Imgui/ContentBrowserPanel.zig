const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvents = @import("ImguiEvent.zig");
const ImguiEvent = ImguiEvents.ImguiEvent;
const NewProjectEvent = ImguiEvents.NewProjectEvent;
const OpenProjectEvent = ImguiEvents.OpenProjectEvent;
const ContentBrowserPanel = @This();
const Texture2D = @import("../Textures/Texture2D.zig");

const MAX_PATH_LEN = 260;

mIsVisible: bool = true,
mDirTexture: Texture2D,
mPngTexture: Texture2D,
mBackArrowTexture: Texture2D,
mProjectDirectory: std.ArrayList(u8),
mCurrentDirectory: std.ArrayList(u8),
mProjectFile: ?std.fs.File = null,
var PathGPA: std.heap.GeneralPurposeAllocator(.{}) = .{};

pub fn Init() !ContentBrowserPanel {
    var buffer: [MAX_PATH_LEN * 4]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const cwd_dir_path = try std.fs.cwd().realpathAlloc(fba.allocator(), ".");
    const dir_icon_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd_dir_path, "/assets/textures/foldericon.png" });
    const png_icon_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd_dir_path, "/assets/textures/pngicon.png" });
    const backarrow_icon_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd_dir_path, "/assets/textures/backarrowicon.png" });

    return ContentBrowserPanel{
        .mIsVisible = true,
        .mDirTexture = try Texture2D.InitPath(dir_icon_path),
        .mPngTexture = try Texture2D.InitPath(png_icon_path),
        .mBackArrowTexture = try Texture2D.InitPath(backarrow_icon_path),
        .mProjectDirectory = std.ArrayList(u8).init(PathGPA.allocator()),
        .mCurrentDirectory = std.ArrayList(u8).init(PathGPA.allocator()),
        .mProjectFile = null,
    };
}

pub fn Deinit(self: *ContentBrowserPanel) void {
    self.mDirTexture.Deinit();
    self.mPngTexture.Deinit();
    self.mBackArrowTexture.Deinit();
    self.mProjectDirectory.deinit();
    self.mProjectDirectory.deinit();
    if (self.mProjectFile != null) {
        self.mProjectFile.?.close();
    }
}

pub fn OnImguiRender(self: *ContentBrowserPanel) !void {
    if (self.mIsVisible == false) return;

    _ = imgui.igBegin("ContentBrowser", null, 0);
    defer imgui.igEnd();

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

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.7, .y = 0.2, .z = 0.3, .w = 1.0 });
    _ = imgui.igImageButton("back", @constCast(@ptrCast(&self.mBackArrowTexture.GetID())), .{ .x = thumbnail_size, .y = thumbnail_size }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0, .z = 0, .w = 0 }, .{ .x = 1, .y = 1, .z = 1, .w = 1 });
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
            icon_ptr = &self.mDirTexture;
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) {
            icon_ptr = &self.mPngTexture;
        }
        if (icon_ptr) |texture| {
            var texture_id = texture.GetID();
            texture.Bind(0);
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.8, .y = 0.3, .z = 0.2, .w = 1.0 });
            _ = imgui.igImageButtonEx(
                texture_id,
                @ptrCast(&texture_id),
                .{ .x = thumbnail_size, .y = thumbnail_size },
                .{ .x = 0.0, .y = 0.0 },
                .{ .x = 1.0, .y = 1.0 },
                .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
                .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
                0,
            );
            imgui.igPopStyleColor(1);

            if (entry.kind == .directory and imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
                _ = try self.mCurrentDirectory.writer().write("/");
                _ = try self.mCurrentDirectory.writer().write(entry.name);
            }

            imgui.igTextWrapped(@ptrCast(entry.name));
            imgui.igNextColumn();
        }
    }
}

fn OnTogglePanelEvent(self: *ContentBrowserPanel) void {
    self.mIsVisible = !self.mIsVisible;
}

fn OnNewProjectEvent(self: *ContentBrowserPanel, event: NewProjectEvent) !void {
    if (self.mProjectDirectory.items.len != 0) {
        self.mProjectDirectory.clearAndFree();
        self.mCurrentDirectory.clearAndFree();
    }
    _ = try self.mProjectDirectory.writer().write(event._Path);
    _ = try self.mCurrentDirectory.writer().write(event._Path);

    var dir = try std.fs.openDirAbsolute(self.mProjectDirectory.items, .{});
    defer dir.close();

    const file_exists: bool = blk: {
        dir.access("NewGame.imprj", .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    var buffer: [MAX_PATH_LEN]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const file_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self.mProjectDirectory.items, "NewGame.imprj" });

    if (file_exists == false) {
        self.mProjectFile = try std.fs.createFileAbsolute(file_path, .{});
    } else {
        self.mProjectFile = try std.fs.openFileAbsolute(file_path, .{});
    }
}

fn OnOpenProjectEvent(self: *ContentBrowserPanel, event: OpenProjectEvent) !void {
    if (self.mProjectDirectory.items.len != 0) {
        self.mProjectDirectory.clearAndFree();
        self.mCurrentDirectory.clearAndFree();
    }
    _ = try self.mProjectDirectory.writer().write(event._Path);
    _ = try self.mCurrentDirectory.writer().write(event._Path);
    self.mProjectFile = try std.fs.openFileAbsolute(event._Path, .{});
}
