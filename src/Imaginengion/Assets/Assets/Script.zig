const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const Script = @This();

pub const ScriptType = enum {
    None,
    EntityScript,
    CollisionScript,
};

mType: ScriptType = .None,
mLib: std.DynLib = undefined,

pub fn Init(path: []const u8, script_type: ScriptType) !Script {
    var buffer: [260 * 2]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const cwd_dir_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd_dir_path, path });

    return Script{
        .mLib = std.DynLib.open(abs_path),
        .mType = script_type,
    };
}

pub fn Deinit(self: Script) void {
    self.mLib.close();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == Script) {
            break :blk i;
        }
    }
};
