const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const Script = @This();

const imgui = @import("../../Core/CImports.zig").imgui;

mLib: std.DynLib = undefined,

pub fn Init(path: []const u8) !Script {
    var buffer: [260 * 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const cwd_dir_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd_dir_path, path });

    return Script{
        .mLib = try std.DynLib.open(abs_path),
    };
}

pub fn Deinit(self: *Script) void {
    self.mLib.close();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == Script) {
            break :blk i;
        }
    }
};

pub fn EditorRender(self: *Script) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}
