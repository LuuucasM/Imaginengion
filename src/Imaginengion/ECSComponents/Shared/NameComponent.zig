const std = @import("std");
const NameComponent = @This();
const EngineContext = @import("../../Core/EngineContext.zig");

const Inspector = @import("../../UI/Inspector.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");

pub const Editable: bool = true;
pub const Name: []const u8 = "NameComponent";
pub const empty: NameComponent = .{
    .mName = .empty,
};

mName: std.ArrayList(u8) = .empty,

pub fn Deinit(self: *NameComponent, _: *EngineContext, keep_allocator: std.mem.Allocator) void {
    self.mName.deinit(keep_allocator);
}

pub fn Clone(self: *const NameComponent, _: *EngineContext, keep_allocator: std.mem.Allocator) !NameComponent {
    return .{ .mName = try self.mName.clone(keep_allocator) };
}

pub fn UIRender(self: *NameComponent, ui: *Inspector.Builder) !void {
    try ui.Text(&self.mName, "Name", .{});
}

const Json = JsonUtils.JsonFields(NameComponent, .{ .Name = "mName" });
pub const jsonStringify = Json.jsonStringify;
pub const jsonParse = Json.jsonParse;
