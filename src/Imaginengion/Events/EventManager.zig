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
    comptime var union_fields: [phase_fields.len]builtin.Type.UnionField = undefined;
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
    const TaggedUnionType = CategoryTaggedEventUnion(EventCategoriesType, EventUnionType);

    return struct {
        pub const ClearMode = struct {
            .ClearAndFree,
            .ClearRetainingCapacity,
        };
        const Self = @This();
        pub const EventCategoriesT = EventCategoriesType;
        pub const EventT = EventUnionType;
        pub const TaggedUnionT = TaggedUnionType;

        mEventsArray: std.MultiArrayList(TaggedUnionType) = .{},

        pub fn Deinit(self: *Self, engine_allocator: std.mem.Allocator) void {
            self.mEventsArray.deinit(engine_allocator);
        }

        pub fn Insert(self: *Self, engine_allocator: std.mem.Allocator, phase_event: TaggedUnionT) !void {
            try self.mEventsArray.append(engine_allocator, phase_event);
        }

        /// Process events for a specific phase.
        /// If `callback_fn` returns `true`, the event is removed (swap-remove, order not preserved).
        pub fn ProcessPhase(
            self: *Self,
            phase: EventCategoriesT,
            engine_context: *EngineContext,
            callback_context: anytype,
            callback_fn: fn (@TypeOf(callback_context), *EngineContext, EventT) anyerror!bool,
        ) !void {
            const slices = self.mEventsArray.slice();

            const events = slices.items(phase);

            for (events) |event| {
                _ = try callback_fn(callback_context, engine_context, event);
            }
        }

        pub fn EventsReset(self: *Self, engine_allocator: std.mem.Allocator, clear_mode: ClearMode) void {
            switch (clear_mode) {
                .ClearAndFree => self.mEventsArray.clearAndFree(engine_allocator),
                .ClearRetainingCapacity => self.mEventsArray.clearRetainingCapacity(),
            }
        }
    };
}
