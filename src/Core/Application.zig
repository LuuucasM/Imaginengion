const std = @import("std");
const Application: type = @This();
const config = @import("config");

_IsRunning: bool = true,
_IsMinimized: bool = false,
_EngineAllocator: std.mem.Allocator,
//TODO: _Window: Window,
//TODO: _Program: Program,

pub fn Init(EngineAllocator: std.mem.Allocator) !*Application {
    const app: *Application = try EngineAllocator.create(Application);
    app = .{
        ._EngineAllocator = EngineAllocator,
    };
}
pub fn Deinit(app: *Application) void {
    app.*._EngineAllocator.destroy(app);
}

pub fn Run(app: *Application) void {
    _ = app;
    //TODO: Prograom.OnUpdate()
}

//TODO: pub fn OnEvent(event: Event) void {
//TODO:
//TODO: }

fn OnWindowClose(app: *Application) bool {
    _ = app;
    return true;
}

fn OnWindowResize(app: *Application, width: usize, height: usize) bool {
    _ = app;
    _ = width;
    _ = height;
    return false;
}
