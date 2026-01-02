const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ScriptAsset = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

const imgui = @import("../../Core/CImports.zig").imgui;

const EntityComponents = @import("../../GameObjects/Components.zig");
const EntityInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityUpdateScript = EntityComponents.OnUpdateScript;

const SceneComponents = @import("../../Scene/SceneComponents.zig");
const SceneSceneStartScript = SceneComponents.OnSceneStartScript;

pub const ScriptType = enum(u8) {
    //Game object scripts
    EntityInputPressed = 0,
    EntityUpdateInput = 1,

    //Scene Scripts
    SceneSceneStart = 2,
};

mLib: std.DynLib = undefined,
mScriptType: ScriptType = undefined,
mRunFunc: ?*anyopaque = null,

pub fn Init(self: *ScriptAsset, asset_allocator: std.mem.Allocator, abs_path: []const u8, _: []const u8, _: std.fs.File) !void {

    //spawn a child to handle compiling the zig file into a dll
    const file_arg = try std.fmt.allocPrint(asset_allocator, "-Dscript_abs_path={s}", .{abs_path});
    defer asset_allocator.free(file_arg);
    //defer allocator.free(file_arg);

    var child = std.process.Child.init(
        &[_][]const u8{
            "zig",
            "build",
            "--build-file",
            "build_dyn.zig",
            file_arg,
        },
        asset_allocator,
    );
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const result = try child.wait();
    std.log.debug("child [{s}] exited with code {}\n", .{ abs_path, result });

    //get the path of the newly create dyn lib and open it
    const dyn_path = try std.fmt.allocPrint(asset_allocator, "zig-out/bin/{s}.dll", .{std.fs.path.basename(abs_path)});
    defer asset_allocator.free(dyn_path);

    self.mLib = try std.DynLib.open(dyn_path);

    const script_type_func = self.mLib.lookup(*const fn () ScriptType, "GetScriptType").?;

    self.mScriptType = script_type_func();

    self.mRunFunc = self.mLib.lookup(EntityInputPressedScript.RunFuncSig, "Run").?;
}

pub fn Deinit(self: *ScriptAsset) !void {
    self.mLib.close();
}

pub fn Run(self: *ScriptAsset, args: anytype) bool {
    return @call(.auto, self.mRunFunc, args);
}

pub const Ind: usize = blk: {
    for (AssetsList, 0..) |asset_type, i| {
        if (asset_type == ScriptAsset) {
            break :blk i + 2; // add 2 because 0 is parent component and 1 is child component provided by the ECS
        }
    }
};

pub const Category: ComponentCategory = .Unique;

pub fn EditorRender(self: *ScriptAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}
