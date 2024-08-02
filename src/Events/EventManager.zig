const std = @import("std");
const assert = std.debug.assert;
const Event = @import("Event.zig");
const EventManager = @This();

var EVENTMANAGER: *EventManager = undefined;

_InputEventArena: std.heap.ArenaAllocator,
_WindowEventArena: std.heap.ArenaAllocator,
_EngineAllocator: std.mem.Allocator,

pub fn Init(EngineAllocator: std.mem.Allocator) !void {
    EVENTMANAGER = try EngineAllocator.create(EventManager);
    EVENTMANAGER.* = .{
        ._InputEventArena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        ._WindowEventArena = std.heap.ArenaAllocator.init(std.heap.page_allocator),
        ._EngineAllocator = EngineAllocator,
    };
}

pub fn Deinit() void {
    EVENTMANAGER._InputEventArena.deinit();
    EVENTMANAGER._WindowEventArena.deinit();
    EVENTMANAGER._EngineAllocator.destroy(EVENTMANAGER);
}

pub fn Insert(event: anytype) !void {
    const T = @TypeOf(event);
    assert(@hasDecl(T, "GetEventName"));
    const ptr = switch (event.GetEventName()) {
        .EN_KeyPressed, .EN_KeyReleased, .EN_MouseButtonPressed, .EN_MouseButtonReleased, .EN_MouseMoved, .EN_MouseScrolled => try EVENTMANAGER._InputEventArena.allocator().create(T),
        .EN_WindowClose, .EN_WindowResize => try EVENTMANAGER._WindowEventArena.allocator().create(T),
    };
    ptr.* = event;
}

//pub fn ProcessWindowEvents(callbackfn: fn (Event) void) void {
//    var it = EventManager._WindowEventArena.state.buffer_list.first;
//    while (it) |node| {
//        callbackfn(node.data);
//        it = node.next;
//    }
//}

pub fn ProcessInputEvents(callbackfn: fn (Event) void) void {
    var it = EVENTMANAGER._InputEventArena.state.buffer_list.first;
    while (it) |node| {
        const object_bytes = @as([*]u8, @ptrCast(node)) + @sizeOf(@TypeOf(node));
        const event: *Event = @ptrCast(@alignCast(object_bytes));
        callbackfn(event.*);
        it = node.next;
    }
}

pub fn EventsReset() void {
    //TODO: make it dynamic freeing
    EVENTMANAGER._InputEventArena.reset(.free_all);
    EVENTMANAGER._WindowEventArena.reset(.free_all);
}
