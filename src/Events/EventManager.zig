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
_EventCallback: *const fn (*Event) void,

pub fn Init(EngineAllocator: std.mem.Allocator, eventCallback: fn (*Event) void) !void {
    EventManager = try EngineAllocator.create(Self);
    EventManager.* = .{
        ._InputEventPool = std.heap.MemoryPool(Event).init(std.heap.page_allocator),
        ._WindowEventPool = std.heap.MemoryPool(Event).init(std.heap.page_allocator),
        ._EngineAllocator = EngineAllocator,
        ._EventCallback = eventCallback,
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
    const end_index = switch (eventCategory) {
        .EC_Input => EventManager._InputEventPool.arena.state.end_index,
        .EC_Window => EventManager._WindowEventPool.arena.state.end_index,
    };

    var current_index: usize = 0;
    while (it) |node| {
        defer current_index += 1;
        defer it = node.next;

        //only want to itereate what we have allocated not the full capacity
        if (current_index >= end_index) break;

        //convert raw pointer into event pointer
        //note std.SlinglyLinkedList(usize).Node is the type for BufNode which is the type of 'node' internally
        const object_bytes = @as([*]u8, @ptrCast(node)) + @sizeOf(std.SinglyLinkedList(usize).Node);
        const event: *Event = @ptrCast(@alignCast(object_bytes));

        EventManager._EventCallback(event);
    }
}

pub fn EventsReset() void {
    //const capacity = std.heap.ArenaAllocator.ResetMode{ .retain_with_limit = 20 };
    _ = EventManager._InputEventPool.reset(.free_all);
    _ = EventManager._WindowEventPool.reset(.free_all);
}
