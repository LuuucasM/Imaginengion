const std = @import("std");
const Application = @import("Core/Application.zig");
const Program = @import("Programs/Program.zig");
const EventManager = @import("Events/EventManager.zig");

pub fn main() !void {
    std.log.info("Initializing Application", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const EngineAllocator = gpa.allocator();
    defer _ = gpa.deinit();
    var application = try Application.Init(EngineAllocator);
    application.mProgram = try Program.Init(EngineAllocator, &application.mWindow);
    try EventManager.Init(EngineAllocator, &application);
    std.log.info("Running Application", .{});
    try application.Run();
    std.log.info("Deinitializing Application", .{});
    try application.Deinit();
    std.log.info("Exiting main", .{});
}
