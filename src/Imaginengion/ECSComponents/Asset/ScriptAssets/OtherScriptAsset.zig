const std = @import("std");
const OtherScriptAsset = @This();


const EntityComponents = @import("../../EComponents.zig");
const EntityInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityOnUpdateScript = EntityComponents.OnUpdateScript;

const SceneComponents = @import("../../SComponents.zig");
const SceneSceneStartScript = SceneComponents.OnSceneStartScript;
const SceneOnUpdateScript = SceneComponents.OnUpdateScript;
const SceneInputPressedScript = SceneComponents.InputPressedScript;

const EngineContext = @import("../../../Core/EngineContext.zig");
const ScriptResult = @import("../ScriptAsset.zig").ScriptResult;
const ScriptType = @import("../ScriptAsset.zig").ScriptType;

mLib: std.DynLib = undefined,
mScriptType: ScriptType = undefined,
mRunFunc: *anyopaque = undefined,

pub fn Init(self: *OtherScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.fs.File) !void {

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
    std.log.info("script {s} compile success!\n", .{rel_path});

    //get the path of the newly create dyn lib and open it
    const dyn_path = try std.fmt.allocPrint(engine_context.FrameAllocator(), "zig-out/bin/{s}.dll", .{std.fs.path.basename(abs_path)});

    self.mLib = try std.DynLib.open(dyn_path);

    const script_type_func = self.mLib.lookup(*const fn () ScriptType, "GetScriptType").?;

    self.mScriptType = script_type_func();

    self.mRunFunc = switch (self.mScriptType) {
        .EntityInputPressed => @constCast(self.mLib.lookup(EntityInputPressedScript.RunFuncSig, "Run").?),
        .EntityOnUpdate => @constCast(self.mLib.lookup(EntityOnUpdateScript.RunFuncSig, "Run").?),
        .EntityOnCollisionBegin => @constCast(self.mLib.lookup(EntityComponents.OnCollisionBeginScript.RunFuncSig, "Run").?),
        .EntityOnCollisionEnd => @constCast(self.mLib.lookup(EntityComponents.OnCollisionEndScript.RunFuncSig, "Run").?),
        .EntityOnPreSolve => @constCast(self.mLib.lookup(EntityComponents.OnPreSolveScript.RunFuncSig, "Run").?),
        .EntityOnPhysicsUpdate => @constCast(self.mLib.lookup(EntityComponents.OnPhysicsUpdateScript.RunFuncSig, "Run").?),
        .EntityOnPointerEvent => @constCast(self.mLib.lookup(EntityComponents.OnPointerEventScript.RunFuncSig, "Run").?),
        .EntityOnUIEvent => @constCast(self.mLib.lookup(EntityComponents.OnUIEventScript.RunFuncSig, "Run").?),
        .SceneSceneStart => @constCast(self.mLib.lookup(SceneSceneStartScript.RunFuncSig, "Run").?),
        .SceneInputPressed => @constCast(self.mLib.lookup(SceneInputPressedScript.RunFuncSig, "Run").?),
        .SceneOnUpdate => @constCast(self.mLib.lookup(SceneOnUpdateScript.RunFuncSig, "Run").?),
        .SceneOnPhysicsUpdate => @constCast(self.mLib.lookup(SceneComponents.OnPhysicsUpdateScript.RunFuncSig, "Run").?),
    };
}

pub fn Deinit(self: *OtherScriptAsset, _: *EngineContext) void {
    self.mLib.close();
}

pub fn Run(self: *OtherScriptAsset, comptime script_type: type, args: anytype) ScriptResult {
    return @call(.auto, @as(script_type.RunFuncSig, @ptrCast(self.mRunFunc)), args);
}
