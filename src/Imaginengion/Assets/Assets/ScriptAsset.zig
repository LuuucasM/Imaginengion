const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ScriptAsset = @This();

const imgui = @import("../../Core/CImports.zig").imgui;

pub const ScriptType = enum(u8) {
    //Game object scripts
    OnInputPressed = 0,
    OnUpdateInput = 1,

    //Scene Scripts
    OnSceneStart = 2,
};

mLib: std.DynLib = undefined,
mScriptType: ScriptType = undefined,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) !ScriptAsset {

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
    std.log.debug("child [{s}] exited with code {}", .{ abs_path, result });

    //get the path of the newly create dyn lib and open it
    const dyn_path = try std.fmt.allocPrint(allocator, "zig-out/bin/{s}.dll", .{std.fs.path.basename(abs_path)});
    defer allocator.free(dyn_path);

    var lib = try std.DynLib.open(dyn_path);
    const GetScriptTypeFunc = lib.lookup(*const fn () ScriptType, "GetScriptType").?;

    return ScriptAsset{
        .mLib = lib,
        .mScriptType = GetScriptTypeFunc(),
    };
}

pub fn Deinit(self: *ScriptAsset) !void {
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
