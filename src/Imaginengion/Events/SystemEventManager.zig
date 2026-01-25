const std = @import("std");
const Application = @import("../Core/Application.zig");
const SystemEvent = @import("SystemEvent.zig").SystemEvent;
const SystemEventCategory = @import("SystemEvent.zig").SystemEventCategory;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const SystemEventManager = @This();

pub const ClearMode = enum(u8) {
    ClearAndFree,
    ClearRetainingCapacity,
};

_InputEventPool: std.ArrayList(SystemEvent) = .{},
_WindowEventPool: std.ArrayList(SystemEvent) = .{},
_Application: *Application = undefined,

pub fn Init(self: *SystemEventManager, application: *Application) void {
    self._Application = application;
}

pub fn Deinit(self: *SystemEventManager, engine_allocator: std.mem.Allocator) void {
    self._InputEventPool.deinit(engine_allocator);
    self._WindowEventPool.deinit(engine_allocator);
}

pub fn Insert(self: *SystemEventManager, engine_allocator: std.mem.Allocator, event: SystemEvent) !void {
    switch (event.GetEventCategory()) {
        .EC_Input => try self._InputEventPool.append(engine_allocator, event),
        .EC_Window => try self._WindowEventPool.append(engine_allocator, event),
        else => @panic("Default Events are not allowed!\n"),
    }
}

pub fn ProcessEvents(self: *SystemEventManager, engine_context: *EngineContext, eventCategory: SystemEventCategory) !void {
    const zone = Tracy.ZoneInit("ProcessEvents", @src());
    defer zone.Deinit();
    const array = switch (eventCategory) {
        .EC_Input => self._InputEventPool,
        .EC_Window => self._WindowEventPool,
        else => @panic("Default Events are not allowed!\n"),
    };

    //first pass to update input state for the frame
    var final_mouse_pos = engine_context.mInputManager.GetMousePosition();
    var final_mouse_scroll = engine_context.mInputManager.GetMouseScrolled();
    for (array.items) |event| {
        switch (event) {
            .ET_InputPressed => |e| try engine_context.mInputManager.SetInputPressed(e._InputCode),
            .ET_InputReleased => |e| engine_context.mInputManager.SetInputReleased(e._InputCode),
            .ET_MouseMoved => |e| final_mouse_pos = @Vector(2, f32){ e._MouseX, e._MouseY },
            .ET_MouseScrolled => |e| final_mouse_scroll = @Vector(2, f32){ e._XOffset, e._YOffset },
            else => {},
        }
    }
    engine_context.mInputManager.SetMousePosition(final_mouse_pos);
    engine_context.mInputManager.SetMouseScrolled(final_mouse_scroll);

    //second pass to propegate events
    for (array.items) |*event| {
        try self._Application.OnEvent(event);
    }
}

pub fn EventsReset(self: *SystemEventManager, engine_allocator: std.mem.Allocator, clear_mode: ClearMode) void {
    const zone = Tracy.ZoneInit("System Event Reset", @src());
    defer zone.Deinit();

    switch (clear_mode) {
        .ClearAndFree => {
            _ = self._InputEventPool.clearAndFree(engine_allocator);
            _ = self._WindowEventPool.clearAndFree(engine_allocator);
        },
        .ClearRetainingCapacity => {
            _ = self._InputEventPool.clearRetainingCapacity();
            _ = self._WindowEventPool.clearRetainingCapacity();
        },
    }
}
