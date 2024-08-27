const std = @import("std");
const assert = std.debug.assert;
const Event = @import("Event.zig").Event;
const EventCategory = @import("EventEnums.zig").EventCategory;
const EventType = @import("EventEnums.zig").EventType;
const Self = @This();

var EventManager: *Self = undefined;

_InputEventPool: std.heap.MemoryPool(Event),
_WindowEventPool: std.heap.MemoryPool(Event),
_EngineAllocator: std.mem.Allocator,
_InputEventCallback: *const fn (*Event) void,
_WindowEventCallback: *const fn (*Event) void,

pub fn Init(EngineAllocator: std.mem.Allocator, inputEventCallback: fn (*Event) void, windowEventCallback: fn (*Event) void) !void {
    EventManager = try EngineAllocator.create(Self);
    EventManager.* = .{
        ._InputEventPool = std.heap.MemoryPool(Event).init(std.heap.page_allocator),
        ._WindowEventPool = std.heap.MemoryPool(Event).init(std.heap.page_allocator),
        ._EngineAllocator = EngineAllocator,
        ._InputEventCallback = inputEventCallback,
        ._WindowEventCallback = windowEventCallback,
    };
}

pub fn Deinit() void {
    EventManager._InputEventPool.deinit();
    EventManager._WindowEventPool.deinit();
    EventManager._EngineAllocator.destroy(EventManager);
}

pub fn Insert(event: Event) !void {
    const ptr = switch (event.GetEventCategory()) {
        .EC_Input => try EventManager._InputEventPool.create(),
        .EC_Window => try EventManager._WindowEventPool.create(),
    };
    ptr.* = event;
}

pub fn ProcessEvents(eventCategory: EventCategory) void {
    var it = switch (eventCategory) {
        .EC_Input => EventManager._InputEventPool.arena.state.buffer_list.first,
        .EC_Window => EventManager._WindowEventPool.arena.state.buffer_list.first,
    };
    const callback = switch (eventCategory) {
        .EC_Input => EventManager._InputEventCallback,
        .EC_Window => EventManager._WindowEventCallback,
    };
    while (it) |node| {
        //convert raw pointer into event pointer
        //note std.SlinglyLinkedList(usize).Node is the type for BufNode which is the type of 'node' internally
        const object_bytes = @as([*]u8, @ptrCast(node)) + @sizeOf(std.SinglyLinkedList(usize).Node);
        const event: *Event = @ptrCast(@alignCast(object_bytes));

        callback(event);

        it = node.next;
    }
}

pub fn EventsReset() void {
    _ = EventManager._InputEventPool.reset(.free_all);
    _ = EventManager._WindowEventPool.reset(.free_all);
}
