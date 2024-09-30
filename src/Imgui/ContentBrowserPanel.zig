const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvents = @import("ImguiEvent.zig");
const ImguiEvent = ImguiEvents.ImguiEvent;
const NewProjectEvent = ImguiEvents.NewProjectEvent;
const OpenProjectEvent = ImguiEvents.OpenProjectEvent;
const ContentBrowserPanel = @This();
const Texture2D = @import("../Textures/Texture2D.zig");

const MAX_PATH_LEN = 260;

_P_Open: bool = true,
_DirTexture: Texture2D = .{},
_PngTexture: Texture2D = .{},
_BackArrowTexture: Texture2D = .{},
_ProjectDirectory: []const u8 = "",
_CurrentDirectory: []const u8 = "",
_ProjectFile: std.fs.File = undefined,
_PathGPA: std.heap.GeneralPurposeAllocator(.{}) = undefined,

pub fn Init(self: *ContentBrowserPanel) !void {
    self._P_Open = true;
    self._ProjectDirectory = "";
    self._CurrentDirectory = "";
    self._PathGPA = std.heap.GeneralPurposeAllocator(.{}){};

    var buffer: [MAX_PATH_LEN * 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const cwd_dir_path = try std.fs.cwd().realpathAlloc(fba.allocator(), ".");
    const dir_icon_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd_dir_path, "/assets/textures/foldericon.png" });

    try self._DirTexture.InitPath(dir_icon_path);
    fba.allocator().free(dir_icon_path);

    const png_icon_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd_dir_path, "/assets/textures/pngicon.png" });
    try self._PngTexture.InitPath(png_icon_path);
    fba.allocator().free(png_icon_path);

    const backarrow_icon_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ cwd_dir_path, "/assets/textures/backarrowicon.png" });
    try self._BackArrowTexture.InitPath(backarrow_icon_path);
}

pub fn Deinit(self: *ContentBrowserPanel) void {
    if (self._ProjectDirectory.len != 0) {
        self._ProjectFile.close();
    }
}

pub fn OnImguiRender(self: *ContentBrowserPanel) !void {
    if (self._P_Open == false) return;

    _ = imgui.igBegin("ContentBrowser", null, 0);
    defer imgui.igEnd();

    //if we dont have a project directory yet dont try to print stuff
    if (self._CurrentDirectory.len == 0) return;

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
    if (std.mem.eql(u8, self._CurrentDirectory, self._ProjectDirectory) == true) return;

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0, .y = 0, .z = 0, .w = 0 });
    _ = imgui.igImageButton("back", @constCast(@ptrCast(&self._BackArrowTexture.GetID())), .{ .x = thumbnail_size, .y = thumbnail_size }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0, .z = 0, .w = 0 }, .{ .x = 1, .y = 1, .z = 1, .w = 1 });
    imgui.igPopStyleColor(1);

    if (imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
        const new_dir = try self._PathGPA.allocator().dupe(u8, std.fs.path.dirname(self._CurrentDirectory).?);
        self._PathGPA.allocator().free(self._CurrentDirectory);
        self._CurrentDirectory = new_dir;
    }

    imgui.igTextWrapped("Back");
    imgui.igNextColumn();
}

fn RenderDirectoryContents(self: *ContentBrowserPanel, thumbnail_size: f32) !void {
    const dir = try std.fs.openDirAbsolute(self._CurrentDirectory, .{ .iterate = true });

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        var icon_ptr: ?*Texture2D = null;
        if (entry.kind == .directory) {
            icon_ptr = &self._DirTexture;
        } else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) {
            icon_ptr = &self._PngTexture;
        }
        if (icon_ptr) |texture| {
            var texture_id = texture.GetID();
            imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.8, .y = 0.3, .z = 0.2, .w = 1 });
            _ = imgui.igImageButton(
                @ptrCast(entry.name),
                @ptrCast(&texture_id),
                .{ .x = thumbnail_size, .y = thumbnail_size },
                .{ .x = 0, .y = 1 },
                .{ .x = 1, .y = 0 },
                .{ .x = 0, .y = 0, .z = 0, .w = 0 },
                .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            );
            imgui.igPopStyleColor(1);

            if (entry.kind == .directory and imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
                const new_dir = try std.fs.path.join(self._PathGPA.allocator(), &[_][]const u8{ self._CurrentDirectory, entry.name });
                self._PathGPA.allocator().free(self._CurrentDirectory);
                self._CurrentDirectory = new_dir;
            }

            imgui.igTextWrapped(@ptrCast(entry.name));
            imgui.igNextColumn();
        }
    }
}

fn OnTogglePanelEvent(self: *ContentBrowserPanel) void {
    self._P_Open = !self._P_Open;
}

fn OnNewProjectEvent(self: *ContentBrowserPanel, event: NewProjectEvent) !void {
    self._ProjectDirectory = event._Path;
    self._CurrentDirectory = try self._PathGPA.allocator().dupe(u8, event._Path);

    var buffer: [MAX_PATH_LEN]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);

    const file_path = try std.fs.path.join(fba.allocator(), &[_][]const u8{ self._ProjectDirectory, "NewGame.imprj" });
    self._ProjectFile = try std.fs.createFileAbsolute(file_path, .{});
}

fn OnOpenProjectEvent(self: *ContentBrowserPanel, event: OpenProjectEvent) !void {
    self._ProjectDirectory = std.fs.path.dirname(event._Path).?;
    self._CurrentDirectory = try self._PathGPA.allocator().dupe(u8, std.fs.path.dirname(event._Path).?);
    self._ProjectFile = try std.fs.openFileAbsolute(event._Path, .{});
}
