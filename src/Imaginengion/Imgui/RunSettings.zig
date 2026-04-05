const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const FileMetaData = @import("../Assets/Assets/FileMetaData.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const Player = @import("../Players/Player.zig");
const RunSettings = @This();

_P_Open: bool = false,
mRunPlayer: ?Player = null,

pub fn Init(self: RunSettings) void {
    _ = self;
}

pub fn OnImguiRender(self: RunSettings, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("RunSettings OIR", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    _ = imgui.igBegin("RunSettings", &self._P_Open, 0);
    defer imgui.igEnd();

    const frame_allocator = engine_context.FrameAllocator();

    const player_name: [*:0]const u8 = blk: {
        if (self.mRunPlayer) |player| {
            // assuming Player has a name getter
            break :blk std.fmt.allocPrintSentinel(frame_allocator, "{s}", .{player.GetName()}, 0);
        } else {
            break :blk "None";
        }
    };

    imgui.igText("Run Player:");
    imgui.igButton(player_name, .{ .x = 200, .y = 0 });

    if (imgui.igBeginDragDropTarget()) {
        if (imgui.igAcceptDragDropPayload("PlayerRef", imgui.ImGuiDragDropFlags_None)) |payload| {
            const player = @as(Player, @ptrCast(@alignCast(payload.*.Data)));
            self.mRunPlayer = player;
        }
        imgui.igEndDragDropTarget();
    }

    if (self.mRunPlayer != null) {
        if (imgui.igButton("Clear", .{ .x = 0, .y = 0 })) {
            self.mRunPlayer = null;
        }
    }
}

pub fn OnTogglePanelEvent(self: *RunSettings) void {
    self._P_Open = !self._P_Open;
}
