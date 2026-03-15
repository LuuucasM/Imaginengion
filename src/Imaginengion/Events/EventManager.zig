const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const builtin = @import("builtin");

fn CategoryTaggedEventUnion(EventCategories: type, EventUnion: type) type {
    const phase_name = @typeName(EventCategories);
    const phase_info = @typeInfo(EventCategories);
    switch (phase_info) {
        .@"enum" => {},
        else => @compileError(phase_name ++ " event phases must be an enum"),
    }

    const event_name = @typeName(EventUnion);
    const event_info = @typeInfo(EventUnion);
    switch (event_info) {
        .@"union" => |u| {
            if (u.tag_type == null) {
                @compileError(event_name ++ " must be a tagged union (e.g. `union(enum)`)");
            }
        },
        else => @compileError(event_name ++ " must be a union (e.g. `union(enum)` )"),
    }

    const phase_fields = std.meta.fields(EventCategories);

    comptime var union_fields: [phase_fields.len]std.builtin.Type.UnionField = undefined;
    inline for (phase_fields, 0..) |f, i| {
        union_fields[i] = .{
            .name = f.name,
            .type = EventUnion,
            .alignment = @alignOf(EventUnion),
        };
    }

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = EventCategories,
        .fields = &union_fields,
        .decls = &.{},
    } });
}

pub fn EventManager(EventCategoriesType: type, EventUnionType: type) type {
    return struct {
        pub const ClearMode = enum {
            ClearAndFree,
            ClearRetainingCapacity,
        };

        pub const EventCallback = struct {
            mCtx: *anyopaque,
            mCallbackFn: *const fn (*anyopaque, *EngineContext, EventUnionType) anyerror!bool,
            mPrev: ?*const EventCallback,
        };

        const Self = @This();
        pub const EventsArrayT = std.EnumArray(EventCategoriesType, std.ArrayList(EventUnionType));

        mEventsArray: EventsArrayT = EventsArrayT.initFill(.{}),

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            var iter = self.mEventsArray.iterator();
            while (iter.next()) |entry| {
                entry.value.deinit(engine_allocator);
            }
        }

        pub fn Insert(self: *Self, engine_allocator: std.mem.Allocator, comptime category: EventCategoriesType, event: EventUnionType) !void {
            try self.mEventsArray.getPtr(category).append(engine_allocator, event);
        }

        /// Process events for a specific phase.
        /// If `callback_fn` returns `true`, the event is removed (swap-remove, order not preserved).
        pub fn ProcessCategory(self: *Self, comptime category: EventCategoriesType, engine_context: *EngineContext, event_callback: *const EventCallback) !void {
            const events = self.mEventsArray.get(category).items;

            var current_callback: ?*const EventCallback = event_callback;
            while (current_callback) |cb| {
                current_callback = cb.mPrev;
                for (events) |event| {
                    _ = try cb.mCallbackFn(cb.mCtx, engine_context, event);
                }
            }
        }

        pub fn EventsReset(self: *Self, engine_allocator: std.mem.Allocator, clear_mode: ClearMode) void {
            var iter = self.mEventsArray.iterator();
            while (iter.next()) |entry| {
                switch (clear_mode) {
                    .ClearAndFree => entry.value.clearAndFree(engine_allocator),
                    .ClearRetainingCapacity => entry.value.clearRetainingCapacity(),
                }
            }
        }
    };
}
