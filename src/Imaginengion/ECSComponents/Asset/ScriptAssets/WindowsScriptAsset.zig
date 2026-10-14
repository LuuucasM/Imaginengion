//! Building and loading a script's DLL on Windows, for ScriptAsset. A build goes to zig-out/bin/<file name>.dll, and what
//! is loaded is a numbered copy of it (<file name>.<generation>.dll): Windows won't let a loaded DLL be written over, and
//! the old build has to stay loaded while the next one is built, to keep running if that one doesn't
const std = @import("std");
const builtin = @import("builtin");
const game_build_options = @import("game_build_options");
const WindowsScriptAsset = @This();

const EngineContext = @import("../../../Core/EngineContext.zig");
const Tracy = @import("../../../Core/Tracy.zig");
const ScriptABI = @import("../../../Scripts/ScriptABI.zig");

mLib: ?std.os.windows.HMODULE = null,
/// the copy that is loaded, deleted once it is unloaded. Empty for a packaged game's, which isn't a copy
mLoadedPath: std.ArrayList(u8) = .empty,

/// Builds the script at abs_path into zig-out/bin/<file name>.dll with the engine's own build (zig build script). A
/// packaged game (-Dprebuilt-scripts) ships its scripts already built, so there it does nothing
pub fn Build(engine_context: *EngineContext, abs_path: []const u8, rel_path: []const u8) !void {
    if (game_build_options.prebuilt_scripts) return;
    const zone = Tracy.ZoneInit("WindowsScriptAsset::Build", @src());
    defer zone.Deinit();

    const name = std.fs.path.basename(abs_path);
    const path_arg = try std.fmt.allocPrint(engine_context.FrameAllocator(), "-Dscript_path={s}", .{abs_path});
    const name_arg = try std.fmt.allocPrint(engine_context.FrameAllocator(), "-Dscript_name={s}", .{name});
    const environ_map = try engine_context.mEnviron.createMap(engine_context.FrameAllocator());

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(engine_context.FrameAllocator(), &.{
        "zig",
        "build",
        "script",
        path_arg,
        name_arg,
        //the same mode as the engine: a script shares the engine's structs (EngineContext and the rest), whose
        //layout can differ between modes, so a script built in another one reads their fields from the wrong place
        "-Doptimize=" ++ @tagName(builtin.mode),
    });
    //a project's script can import the project's files by their names (see build_script.zig)
    const project = &engine_context.mProject;
    if (project.IsOpen() and std.mem.startsWith(u8, abs_path, project.mPath.items)) {
        try argv.append(engine_context.FrameAllocator(), try std.fmt.allocPrint(engine_context.FrameAllocator(), "-Dproject_path={s}", .{project.mPath.items}));
    }

    var child = try std.process.spawn(engine_context.Io(), .{
        .argv = argv.items,
        .environ_map = &environ_map,
        .request_resource_usage_statistics = true,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const result = try child.wait(engine_context.Io());
    if (result != .exited) {
        std.log.err("Unable to correctly compile script {s} it terminated by {s}!", .{ rel_path, @tagName(result) });
        return error.AssetInitFailed;
    }
    if (result.exited != 0) {
        std.log.err("Unable to correctly compile script {s} exited with code {d}!", .{ rel_path, result.exited });
        return error.AssetInitFailed;
    }
    std.log.info("script {s} compile success!\n", .{rel_path});
}

/// Loads the last build of the script at abs_path, as copy number `generation`, and hands back what it exports
pub fn Open(self: *WindowsScriptAsset, engine_context: *EngineContext, abs_path: []const u8, generation: u32) !*const ScriptABI.ScriptInfo {
    const frame_allocator = engine_context.FrameAllocator();
    const name = std.fs.path.basename(abs_path);
    const built_path = try std.fmt.allocPrint(frame_allocator, "zig-out/bin/{s}.dll", .{name});

    var load_path = built_path;
    if (!game_build_options.prebuilt_scripts) {
        load_path = try std.fmt.allocPrint(frame_allocator, "zig-out/bin/{s}.{d}.dll", .{ name, generation });
        const built_w = try std.unicode.utf8ToUtf16LeAllocZ(frame_allocator, built_path);
        const copy_w = try std.unicode.utf8ToUtf16LeAllocZ(frame_allocator, load_path);
        if (!CopyFileW(built_w.ptr, copy_w.ptr, .FALSE).toBool()) {
            std.log.err("Failed to copy {s} to {s} to load it", .{ built_path, load_path });
            return error.AssetInitFailed;
        }
        try self.mLoadedPath.appendSlice(engine_context.EngineAllocator(), load_path);
    }
    errdefer self.Close(engine_context);

    const load_path_w = try std.unicode.utf8ToUtf16LeAllocZ(frame_allocator, load_path);
    self.mLib = LoadLibraryExW(load_path_w.ptr, null, 0) orelse {
        std.log.err("Failed to load DLL: {s}", .{load_path});
        return error.AssetInitFailed;
    };

    const get_info: ScriptABI.GetInfoFn = @ptrCast(@alignCast(GetProcAddress(self.mLib.?, ScriptABI.INFO_SYMBOL) orelse {
        std.log.err("{s} exports no {s}: it wasn't built by zig build script", .{ load_path, ScriptABI.INFO_SYMBOL });
        return error.AssetInitFailed;
    }));
    return get_info();
}

/// Unloads what Open loaded, and deletes the copy
pub fn Close(self: *WindowsScriptAsset, engine_context: *EngineContext) void {
    if (self.mLib) |lib| _ = FreeLibrary(lib);
    self.mLib = null;
    if (self.mLoadedPath.items.len != 0) {
        //best effort: a copy left behind is written over by the next one with its number
        if (std.unicode.utf8ToUtf16LeAllocZ(engine_context.FrameAllocator(), self.mLoadedPath.items)) |path_w| {
            _ = DeleteFileW(path_w.ptr);
        } else |_| {}
    }
    self.mLoadedPath.deinit(engine_context.EngineAllocator());
    self.mLoadedPath = .empty;
}

extern "kernel32" fn LoadLibraryExW(
    lpLibFileName: std.os.windows.LPCWSTR,
    hFile: ?std.os.windows.HANDLE,
    dwFlags: std.os.windows.DWORD,
) callconv(.winapi) ?std.os.windows.HMODULE;

extern "kernel32" fn GetProcAddress(
    hModule: std.os.windows.HMODULE,
    lpProcName: std.os.windows.LPCSTR,
) callconv(.winapi) ?std.os.windows.FARPROC;

extern "kernel32" fn FreeLibrary(
    hModule: std.os.windows.HMODULE,
) callconv(.winapi) std.os.windows.BOOL;

extern "kernel32" fn CopyFileW(
    lpExistingFileName: std.os.windows.LPCWSTR,
    lpNewFileName: std.os.windows.LPCWSTR,
    bFailIfExists: std.os.windows.BOOL,
) callconv(.winapi) std.os.windows.BOOL;

extern "kernel32" fn DeleteFileW(
    lpFileName: std.os.windows.LPCWSTR,
) callconv(.winapi) std.os.windows.BOOL;
