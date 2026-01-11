const std = @import("std");
const AssetsList = @import("../Assets.zig").AssetsList;
const ScriptAsset = @This();
const ComponentCategory = @import("../../ECS/ECSManager.zig").ComponentCategory;

const imgui = @import("../../Core/CImports.zig").imgui;

const EntityComponents = @import("../../GameObjects/Components.zig");
const EntityInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityOnUpdateScript = EntityComponents.OnUpdateScript;

const SceneComponents = @import("../../Scene/SceneComponents.zig");
const SceneSceneStartScript = SceneComponents.OnSceneStartScript;
const EngineContext = @import("../../Core/EngineContext.zig");

pub const ScriptType = enum(u8) {
    //Game object scripts
    EntityInputPressed = 0,
    EntityOnUpdate = 1,

    //Scene Scripts
    SceneSceneStart = 2,
};

mLib: std.DynLib = undefined,
mScriptType: ScriptType = undefined,
mRunFunc: *anyopaque = undefined,

pub fn Init(self: *ScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.fs.File) !void {

    //spawn a child to handle compiling the zig file into a dll
    const file_arg = try std.fmt.allocPrint(engine_context.FrameAllocator(), "-Dscript_abs_path={s}", .{abs_path});
    //defer allocator.free(file_arg);

    var child = std.process.Child.init(
        &[_][]const u8{
            "zig",
            "build",
            "--build-file",
            "build_script.zig",
            file_arg,
        },
        engine_context.FrameAllocator(),
    );
    child.stdin_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    const result = try child.wait();

    if (result != .Exited) {
        std.log.err("Unable to correctly compile script {s} it terminated by {s}!", .{ rel_path, @tagName(result) });
        return error.ScriptAssetInitFail;
    }
    if (result.Exited != 0) {
        std.log.err("Unable to correctly compile script {s} exited with code {d}!", .{ rel_path, result.Exited });
        return error.ScriptAssetInitFail;
    }
    std.log.debug("script {s} compile success!\n", .{rel_path});

    //get the path of the newly create dyn lib and open it
    const dyn_path = try std.fmt.allocPrint(engine_context.FrameAllocator(), "zig-out/bin/{s}.dll", .{std.fs.path.basename(abs_path)});

    self.mLib = try std.DynLib.open(dyn_path);

    const script_type_func = self.mLib.lookup(*const fn () ScriptType, "GetScriptType").?;

    self.mScriptType = script_type_func();

    self.mRunFunc = switch (self.mScriptType) {
        .EntityInputPressed => @constCast(self.mLib.lookup(EntityInputPressedScript.RunFuncSig, "Run").?),
        .EntityOnUpdate => @constCast(self.mLib.lookup(EntityOnUpdateScript.RunFuncSig, "Run").?),
        .SceneSceneStart => @constCast(self.mLib.lookup(SceneSceneStartScript.RunFuncSig, "Run").?),
    };
}

pub fn Deinit(self: *ScriptAsset, _: *EngineContext) !void {
    self.mLib.close();
}

pub fn Run(self: *ScriptAsset, comptime script_type: type, args: anytype) bool {
    return @call(.auto, @as(script_type.RunFuncSig, @ptrCast(self.mRunFunc)), args);
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
