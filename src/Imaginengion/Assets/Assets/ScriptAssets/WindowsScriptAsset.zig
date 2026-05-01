const std = @import("std");
const WindowsScriptAsset = @This();

const imgui = @import("../../../Core/CImports.zig").imgui;

const EntityComponents = @import("../../../GameObjects/Components.zig");
const EntityInputPressedScript = EntityComponents.OnInputPressedScript;
const EntityOnUpdateScript = EntityComponents.OnUpdateScript;

const SceneComponents = @import("../../../Scene/SceneComponents.zig");
const SceneSceneStartScript = SceneComponents.OnSceneStartScript;
const SceneOnUpdateScript = SceneComponents.OnUpdateScript;
const SceneInputPressedScript = SceneComponents.InputPressedScript;

const EngineContext = @import("../../../Core/EngineContext.zig");
const ScriptType = @import("../ScriptAsset.zig").ScriptType;

mLib: std.os.windows.HMODULE = undefined,
mScriptType: ScriptType = undefined,
mRunFunc: *anyopaque = undefined,

pub fn Init(self: *WindowsScriptAsset, engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8, _: std.Io.File) !void {

    //spawn a child to handle compiling the zig file into a dll
    const file_arg = try std.fmt.allocPrint(engine_context.FrameAllocator(), "-Dscript_abs_path={s}", .{abs_path});
    //defer allocator.free(file_arg);
    var child = try std.process.spawn(engine_context.Io(), .{
        .argv = &[_][]const u8{
            "zig",
            "build",
            "--build-file",
            "build_script.zig",
            file_arg,
        },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const result = try child.wait(engine_context.Io());

    if (result != .exited) {
        std.log.err("Unable to correctly compile script {s} it terminated by {s}!", .{ rel_path, @tagName(result) });
        return error.AssetInitFail;
    }
    if (result.exited != 0) {
        std.log.err("Unable to correctly compile script {s} exited with code {d}!", .{ rel_path, result.exited });
        return error.AssetInitFail;
    }
    std.log.info("script {s} compile success!\n", .{rel_path});

    //get the path of the newly create dyn lib and open it
    const dyn_path = try std.fmt.allocPrint(engine_context.FrameAllocator(), "zig-out/bin/{s}.dll", .{std.fs.path.basename(abs_path)});

    const dyn_path_w = try std.unicode.utf8ToUtf16LeAllocZ(engine_context.FrameAllocator(), dyn_path);

    self.mLib = LoadLibraryExW(dyn_path_w.ptr, null, 0) orelse {
        std.log.err("Failed to load DLL: {s}", .{dyn_path});
        return error.AssetInitFail;
    };

    const script_type_func = try LoadSymbol(*const fn () ScriptType, self.mLib, "GetScriptType");
    self.mScriptType = script_type_func();

    self.mRunFunc = GetProcAddress(self.mLib, "Run\x00") orelse {
        std.log.err("Missing exported symbol: Run", .{});
        return error.AssetInitFail;
    };
}

pub fn Deinit(self: *WindowsScriptAsset, _: *EngineContext) !void {
    _ = FreeLibrary(self.mLib);
}

pub fn Run(self: *WindowsScriptAsset, comptime script_type: type, args: anytype) bool {
    const run_func: script_type.RunFuncSig = @ptrCast(self.mRunFunc);
    return @call(.auto, run_func, args);
}

pub fn EditorRender(self: *WindowsScriptAsset) !void {
    _ = self;
    imgui.igText("Nothing for now!", "");
}

pub fn GetScriptType(self: WindowsScriptAsset) ScriptType {
    return self.mScriptType;
}

fn LoadSymbol(comptime T: type, lib: std.os.windows.HMODULE, comptime name: [:0]const u8) !T {
    const addr = GetProcAddress(lib, name.ptr) orelse {
        std.log.err("Missing exported symbol: {s}", .{name});
        return error.ScriptAssetInitFail;
    };

    return @as(T, @ptrCast(@alignCast(addr)));
}

pub extern "kernel32" fn LoadLibraryExW(
    lpLibFileName: std.os.windows.LPCWSTR,
    hFile: ?std.os.windows.HANDLE,
    dwFlags: std.os.windows.DWORD,
) callconv(.winapi) ?std.os.windows.HMODULE;

pub extern "kernel32" fn GetProcAddress(
    hModule: std.os.windows.HMODULE,
    lpProcName: std.os.windows.LPCSTR,
) callconv(.winapi) ?std.os.windows.FARPROC;

pub extern "kernel32" fn FreeLibrary(
    hModule: std.os.windows.HMODULE,
) callconv(.winapi) std.os.windows.BOOL;
