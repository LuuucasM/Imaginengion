const std = @import("std");
const EngineContext = @import("EngineContext.zig");
const IoType = EngineContext.IoType;

pub inline fn MakeIoVTable(comptime io_type: IoType) type {
    const fns = struct {
        fn DirOpenDir(context: ?*anyopaque, dir: std.Io.Dir, sub_path: []const u8, options: std.Io.Dir.OpenOptions) std.Io.Dir.OpenError!std.Io.Dir {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };

            return try inner_io.vtable.dirOpenDir(inner_io.userdata, dir, sub_path, options);
        }
        fn DirStatFile(context: ?*anyopaque, dir: std.Io.Dir, sub_path: []const u8, options: std.Io.Dir.StatFileOptions) std.Io.Dir.StatFileError!std.Io.File.Stat {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };

            return try inner_io.vtable.dirStatFile(inner_io.userdata, dir, sub_path, options);
        }
        fn Now(context: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return inner_io.vtable.now(inner_io.userdata, clock);
        }
        fn DirClose(context: ?*anyopaque, dirs: []const std.Io.Dir) void {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            inner_io.vtable.dirClose(inner_io.userdata, dirs);
        }
        fn ChildWait(context: ?*anyopaque, child: *std.process.Child) std.process.Child.WaitError!std.process.Child.Term {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.childWait(inner_io.userdata, child);
        }
        fn Random(context: ?*anyopaque, buffer: []u8) void {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            inner_io.vtable.random(inner_io.userdata, buffer);
        }
        fn ProcessSpawn(context: ?*anyopaque, options: std.process.SpawnOptions) std.process.SpawnError!std.process.Child {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.processSpawn(inner_io.userdata, options);
        }
        fn FileReadPositional(context: ?*anyopaque, file: std.Io.File, data: []const []u8, offset: u64) std.Io.File.ReadPositionalError!usize {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.fileReadPositional(inner_io.userdata, file, data, offset);
        }
        fn FileClose(context: ?*anyopaque, files: []const std.Io.File) void {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            inner_io.vtable.fileClose(inner_io.userdata, files);
        }
        fn FileStat(context: ?*anyopaque, file: std.Io.File) std.Io.File.StatError!std.Io.File.Stat {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.fileStat(inner_io.userdata, file);
        }
        fn DirOpenFile(context: ?*anyopaque, dir: std.Io.Dir, sub_path: []const u8, flags: std.Io.Dir.OpenFileOptions) std.Io.File.OpenError!std.Io.File {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.dirOpenFile(inner_io.userdata, dir, sub_path, flags);
        }
        fn DirRealPathFile(context: ?*anyopaque, dir: std.Io.Dir, path_name: []const u8, out_buffer: []u8) std.Io.Dir.RealPathFileError!usize {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.dirRealPathFile(inner_io.userdata, dir, path_name, out_buffer);
        }
        fn DirCreateFile(context: ?*anyopaque, dir: std.Io.Dir, sub_path: []const u8, options: std.Io.Dir.CreateFileOptions) std.Io.File.OpenError!std.Io.File {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.dirCreateFile(inner_io.userdata, dir, sub_path, options);
        }
        fn DirRead(context: ?*anyopaque, dir_reader: *std.Io.Dir.Reader, buffer: []std.Io.Dir.Entry) std.Io.Dir.Reader.Error!usize {
            const engine_context: *EngineContext = @ptrCast(@alignCast(context.?));
            const inner_io = switch (io_type) {
                .Threaded => engine_context._Internal.ThreadedIO.io(),
                .Evented => @compileError("evented not implemented for this Io yet\n"),
            };
            return try inner_io.vtable.dirRead(inner_io.userdata, dir_reader, buffer);
        }
    };

    return struct {
        pub const vtable: std.Io.VTable = .{
            .crashHandler = std.Io.noCrashHandler,

            .async = std.Io.noAsync,
            .concurrent = std.Io.failingConcurrent,
            .await = std.Io.unreachableAwait,
            .cancel = std.Io.unreachableCancel,

            .groupAsync = std.Io.noGroupAsync,
            .groupConcurrent = std.Io.failingGroupConcurrent,
            .groupAwait = std.Io.unreachableGroupAwait,
            .groupCancel = std.Io.unreachableGroupCancel,

            .recancel = std.Io.unreachableRecancel,
            .swapCancelProtection = std.Io.unreachableSwapCancelProtection,
            .checkCancel = std.Io.unreachableCheckCancel,

            .futexWait = std.Io.noFutexWait,
            .futexWaitUncancelable = std.Io.noFutexWaitUncancelable,
            .futexWake = std.Io.noFutexWake,

            .operate = std.Io.failingOperate,
            .batchAwaitAsync = std.Io.unreachableBatchAwaitAsync,
            .batchAwaitConcurrent = std.Io.unreachableBatchAwaitConcurrent,
            .batchCancel = std.Io.unreachableBatchCancel,

            .dirCreateDir = std.Io.failingDirCreateDir,
            .dirCreateDirPath = std.Io.failingDirCreateDirPath,
            .dirCreateDirPathOpen = std.Io.failingDirCreateDirPathOpen,
            .dirOpenDir = fns.DirOpenDir,
            .dirStat = std.Io.failingDirStat,
            .dirStatFile = fns.DirStatFile,
            .dirAccess = std.Io.failingDirAccess,
            .dirCreateFile = fns.DirCreateFile,
            .dirCreateFileAtomic = std.Io.failingDirCreateFileAtomic,
            .dirOpenFile = fns.DirOpenFile,
            .dirClose = fns.DirClose,
            .dirRead = fns.DirRead,
            .dirRealPath = std.Io.failingDirRealPath,
            .dirRealPathFile = fns.DirRealPathFile,
            .dirDeleteFile = std.Io.failingDirDeleteFile,
            .dirDeleteDir = std.Io.failingDirDeleteDir,
            .dirRename = std.Io.failingDirRename,
            .dirRenamePreserve = std.Io.failingDirRenamePreserve,
            .dirSymLink = std.Io.failingDirSymLink,
            .dirReadLink = std.Io.failingDirReadLink,
            .dirSetOwner = std.Io.failingDirSetOwner,
            .dirSetFileOwner = std.Io.failingDirSetFileOwner,
            .dirSetPermissions = std.Io.failingDirSetPermissions,
            .dirSetFilePermissions = std.Io.failingDirSetFilePermissions,
            .dirSetTimestamps = std.Io.noDirSetTimestamps,
            .dirHardLink = std.Io.failingDirHardLink,

            .fileStat = fns.FileStat,
            .fileLength = std.Io.failingFileLength,
            .fileClose = fns.FileClose,
            .fileWritePositional = std.Io.failingFileWritePositional,
            .fileWriteFileStreaming = std.Io.noFileWriteFileStreaming,
            .fileWriteFilePositional = std.Io.noFileWriteFilePositional,
            .fileReadPositional = fns.FileReadPositional,
            .fileSeekBy = std.Io.failingFileSeekBy,
            .fileSeekTo = std.Io.failingFileSeekTo,
            .fileSync = std.Io.failingFileSync,
            .fileIsTty = std.Io.unreachableFileIsTty,
            .fileEnableAnsiEscapeCodes = std.Io.unreachableFileEnableAnsiEscapeCodes,
            .fileSupportsAnsiEscapeCodes = std.Io.unreachableFileSupportsAnsiEscapeCodes,
            .fileSetLength = std.Io.failingFileSetLength,
            .fileSetOwner = std.Io.failingFileSetOwner,
            .fileSetPermissions = std.Io.failingFileSetPermissions,
            .fileSetTimestamps = std.Io.noFileSetTimestamps,
            .fileLock = std.Io.failingFileLock,
            .fileTryLock = std.Io.failingFileTryLock,
            .fileUnlock = std.Io.unreachableFileUnlock,
            .fileDowngradeLock = std.Io.failingFileDowngradeLock,
            .fileRealPath = std.Io.failingFileRealPath,
            .fileHardLink = std.Io.failingFileHardLink,

            .fileMemoryMapCreate = std.Io.failingFileMemoryMapCreate,
            .fileMemoryMapDestroy = std.Io.unreachableFileMemoryMapDestroy,
            .fileMemoryMapSetLength = std.Io.unreachableFileMemoryMapSetLength,
            .fileMemoryMapRead = std.Io.unreachableFileMemoryMapRead,
            .fileMemoryMapWrite = std.Io.unreachableFileMemoryMapWrite,

            .processExecutableOpen = std.Io.failingProcessExecutableOpen,
            .processExecutablePath = std.Io.failingProcessExecutablePath,
            .lockStderr = std.Io.unreachableLockStderr,
            .tryLockStderr = std.Io.noTryLockStderr,
            .unlockStderr = std.Io.unreachableUnlockStderr,
            .processCurrentPath = std.Io.failingProcessCurrentPath,
            .processSetCurrentDir = std.Io.failingProcessSetCurrentDir,
            .processSetCurrentPath = std.Io.failingProcessSetCurrentPath,
            .processReplace = std.Io.failingProcessReplace,
            .processReplacePath = std.Io.failingProcessReplacePath,
            .processSpawn = fns.ProcessSpawn,
            .processSpawnPath = std.Io.failingProcessSpawnPath,
            .childWait = fns.ChildWait,
            .childKill = std.Io.unreachableChildKill,

            .progressParentFile = std.Io.failingProgressParentFile,

            .random = fns.Random,
            .randomSecure = std.Io.failingRandomSecure,

            .now = fns.Now,
            .clockResolution = std.Io.failingClockResolution,
            .sleep = std.Io.noSleep,

            .netListenIp = std.Io.failingNetListenIp,
            .netAccept = std.Io.failingNetAccept,
            .netBindIp = std.Io.failingNetBindIp,
            .netConnectIp = std.Io.failingNetConnectIp,
            .netListenUnix = std.Io.failingNetListenUnix,
            .netConnectUnix = std.Io.failingNetConnectUnix,
            .netSocketCreatePair = std.Io.failingNetSocketCreatePair,
            .netSend = std.Io.failingNetSend,
            .netWrite = std.Io.failingNetWrite,
            .netWriteFile = std.Io.failingNetWriteFile,
            .netClose = std.Io.unreachableNetClose,
            .netShutdown = std.Io.failingNetShutdown,
            .netInterfaceNameResolve = std.Io.failingNetInterfaceNameResolve,
            .netInterfaceName = std.Io.unreachableNetInterfaceName,
            .netLookup = std.Io.failingNetLookup,
        };
    };
}
