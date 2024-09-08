const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const ImguiEvent = @import("ImguiEvent.zig").ImguiEvent;
const ContentBrowserPanel = @This();
const Texture2D = @import("../Textures/Texture2D.zig");

_P_Open: bool = true,
_DirTexture: Texture2D = .{},
_PngTexture: Texture2D = .{},
_BackArrowTexture: Texture2D = .{},
_ProjectDirectory: []const u8 = "",
_CurrentDirectory: []const u8 = "",
_ProjectFile: std.fs.File = undefined,

pub fn Init(self: *ContentBrowserPanel) !void {
    self._P_Open = true;
    self._ProjectDirectory = "";
    self._CurrentDirectory = "";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    self._DirTexture.InitPath(try std.fs.path.join(arena.allocator(), &[_][]const u8{ try std.fs.cwd().realpathAlloc(arena.allocator(), "."), "/assets/textures/foldericon.png" }));
    self._PngTexture.InitPath(try std.fs.path.join(arena.allocator(), &[_][]const u8{ try std.fs.cwd().realpathAlloc(arena.allocator(), "."), "/assets/textures/pngicon.png" }));
    self._BackArrowTexture.InitPath(try std.fs.path.join(arena.allocator(), &[_][]const u8{ try std.fs.cwd().realpathAlloc(arena.allocator(), "."), "/assets/textures/backarrowicon.png" }));
}

pub fn Deinit(self: *ContentBrowserPanel) void{
    if (self._ProjectDirectory.len != 0){
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

    RenderBackButton(self, thumbnail_size);

    try RenderDirectoryContents(self, thumbnail_size);
}

pub fn OnImguiEvent(self: *ContentBrowserPanel, event: *ImguiEvent) !void {
    switch (event.*) {
        .ET_TogglePanelEvent => self._P_Open = !self._P_Open,
        .ET_NewProjectEvent => |e| {
            self._ProjectDirectory = e._Path;
            self._CurrentDirectory = e._Path;
            const file_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ self._ProjectDirectory, "NewGame.imprj" });
            defer std.heap.page_allocator.free(file_path);
            self._ProjectFile = try std.fs.createFileAbsolute(file_path, .{});
        },
        .ET_OpenProjectEvent => |e| {
            self._ProjectDirectory = std.fs.path.dirname(e._Path).?;
            self._CurrentDirectory = std.fs.path.dirname(e._Path).?;
            self._ProjectFile = try std.fs.openFileAbsolute(e._Path, .{});
            //in this case e._Path is the full path to the file
            //so first i need to separate the file.imprj file from the rest of the path
            //then i set projectdirectory and current directory to the directory path
            //then i dont open the file but i could one day when i actually use it for more than just a placeholder lol
        },
        else => @panic("That event has not been implemented yet for ContentBrowserPanel!\n"),
    }
}

fn RenderBackButton(self: *ContentBrowserPanel, thumbnail_size: f32) void {
    if (std.mem.eql(u8, self._CurrentDirectory, self._ProjectDirectory) == true) return;

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0, .y = 0, .z = 0, .w = 0 });
    _ = imgui.igImageButton("backarrow.png", @constCast(@ptrCast(&self._BackArrowTexture.GetID())), .{ .x = thumbnail_size, .y = thumbnail_size }, .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 }, .{ .x = 0, .y = 0, .z = 0, .w = 0 }, .{ .x = 1, .y = 1, .z = 1, .w = 1 });
    imgui.igPopStyleColor(1);

    if (imgui.igIsItemHovered(0) == true and imgui.igIsMouseDoubleClicked_Nil(imgui.ImGuiMouseButton_Left) == true) {
        self._CurrentDirectory = std.fs.path.dirname(self._CurrentDirectory).?;
    }

    imgui.igTextWrapped("Back");
    imgui.igNextColumn();
}

fn RenderDirectoryContents(self: *ContentBrowserPanel, thumbnail_size: f32) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const dir = try std.fs.openDirAbsolute(self._CurrentDirectory, .{ .iterate = true });

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const icon_ptr = if (entry.kind == .directory) &self._DirTexture else if (std.mem.eql(u8, std.fs.path.extension(entry.name), ".png") == true) &self._PngTexture else continue;
        var texture_id = icon_ptr.*.GetID();

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
            self._CurrentDirectory = try std.fs.path.join(arena.allocator(), &[_][]const u8{ self._CurrentDirectory, entry.name });
        }

        imgui.igTextWrapped(@ptrCast(entry.name));
        imgui.igNextColumn();
    }
}
