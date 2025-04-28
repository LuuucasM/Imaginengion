const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ScriptAsset = @This();

const imgui = @import("../../Core/CImports.zig").imgui;

pub const ScriptType = enum {
    OnKeyPressed,
};

mLib: std.DynLib = undefined,
mScriptType: ScriptType = undefined,

pub fn Init(path: []const u8) !ScriptAsset {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //get the path of the abs path of the script
    const cwd_dir_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    const abs_path = try std.fs.path.join(allocator, &[_][]const u8{ cwd_dir_path, path });

    //spawn a child to handle compiling the zig file into a dll
    const file_arg = try std.fmt.allocPrint(allocator, "-Dscript_abs_path={s}", .{abs_path});
    var child = std.process.Child.init(
        &[_][]const u8{
            "zig",
            "build",
            "--build-file",
            "build_dyn.zig",
            file_arg,
        },
        allocator,
    );
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const result = try child.wait();
    std.log.debug("child exited with code {}", .{result});

    //get the path of the newly create dyn lib and open it
    const dyn_path = try std.fmt.allocPrint(allocator, "zig-out/bin/{s}.dll", .{std.fs.path.basename(abs_path)});

    var lib = try std.DynLib.open(dyn_path);
    const script_type_func = lib.lookup(*const fn () ScriptType, "GetScriptType").?;

    return ScriptAsset{
        .mLib = lib,
        .mScriptType = script_type_func(),
    };
}

pub fn Deinit(self: *ScriptAsset) void {
    self.mLib.close();
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ScriptAsset) {
            break :blk i;
        }
    }
};

pub fn EditorRender(self: *ScriptAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}
