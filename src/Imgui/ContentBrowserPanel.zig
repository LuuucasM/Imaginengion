const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ContentBrowserPanel = @This();
const Texture2D = @import("../Texture/Texture2D.zig");

_P_Open: bool = true,
_ProjectDirectory: []const u8 = "",
_CurrentDirectory: []const u8 = "",
_DirTexture: Texture2D = .{},
_PngTexture: Texture2D = .{},
_BackArrowTexture: Texture2D = .{},

pub fn Init(self: *ContentBrowserPanel) !void {
    self._P_Open = true;

    const arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    self._DirTexture.InitPath(try std.fs.path.join(arena.allocator(), &[_][]const u8{std.fs.cwd(), "/assets/textures/foldericon.png"}));
    self._PngTexture.InitPath(try std.fs.path.join(arena.allocator(), &[_][]const u8{std.fs.cwd(), "/assets/textures/pngicon.png"}));
    self._BackArrowTexture.InitPath(try std.fs.path.join(arena.allocator(), &[_][]const u8{std.fs.cwd(), "/assets/textures/backarrowicon.png"}));
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

    const panel_width = imgui.igGetContentRegionAvail().x;
    var column_count: i32 = @intFromFloat(panel_width / cell_size);
    if (column_count < 1){
        column_count = 1;
    }

    imgui.igColumns(column_count, 0, false);
    defer imgui.igColumns(1);

    RenderBackButton(self, thumbnail_size);
    try RenderDirectoryContents(self, thumbnail_size);
}

pub fn OnImguiEvent(self: *ContentBrowserPanel, event: *ImguiEvent) void {
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        .ET_NewProjectEvent => |e| {
            self._ProjectDirectory = e._Path;
            self._CurrentDirectory = e._Path;
        },
    }
}

fn RenderBackButton(self: *ContentBrowserPanel, thumbnail_size: f32) void {
    if (std.mem.eql(u8, self._CurrentDirectory, self._ProjectDirectory) == true) return;

    imgui.igPushStyleColor(imgui.ImGuiCol_Button, .{.x = 0, .y = 0, .z = 0, .w = 0});
    imgui.igImageButton(icon_ptr.GetID(), .{.x = thumbnailSize, .y = thumbnailSize}, .{.x = 0, .y = 1}, .{.x = 1, .y = 0});
    imgui.igPopStyleColor();
    
    if (imgui.igIsItemHovered() == true and imgui.igIsMouseDoubleClicked(imgui.ImGuiMouseButton_Left) == true){
        self._CurrentDirectory = std.fs.path.dirname(self._CurrentDirectory).?;
    }

    imgui.igTextWrapped("Back");
    imgui.igNextColumn();
}

fn RenderDirectoryContents(self: *ContentBrowserPanel, thumbnail_size: f32) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const dir=  try std.fs.openDirAbsolute(self._CurrentDirectory, .{.iterate = true});
    
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        imgui.igPushID(entry.name);
        defer imgui.igPopID();

        const icon_ptr = if (entry.kind == directory) &self._DirTexture
                         else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) &self._PngTexture
                         else continue;
        
        imgui.igPushStyleColor(imgui.ImGuiCol_Button, .{.x = 0, .y = 0, .z = 0, .w = 0});
        imgui.igImageButton(icon_ptr.GetID(), .{.x = thumbnail_size, .y = thumbnail_size}, .{.x = 0, .y = 1}, .{.x = 1, .y = 0});
        imgui.igPopStyleColor();

        if (entry.kind == .directory and imgui.igIsItemHovered() == true and imgui.igIsMouseDoubleClicked(imgui.ImGuiMouseButton_Left) == true){
            self._CurrentDirectory = try std.fs.path.join(arena.allocator(), &[_][]const u8{self._CurrentDirectory, entry.name});
        }

        imgui.igTextWrapped(entry.name);
        imgui.igNextColumn();
    }
}