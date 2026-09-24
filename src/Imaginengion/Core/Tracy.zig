const std = @import("std");

const debug_build_options = @import("debug_build_options");
pub const enable_tracy = debug_build_options.enable_tracy;
pub const tracy = if (enable_tracy) @import("Tracy") else void;

pub const Zone = if (enable_tracy) struct {
    mContext: tracy.TracyCZoneCtx,

    pub fn begin(
        comptime name: [*:0]const u8,
        comptime function: ?[*:0]const u8,
        comptime file: [*:0]const u8,
        comptime line: u32,
        comptime color: u32,
    ) Zone {
        const src_loc = &struct {
            pub const value = tracy.___tracy_source_location_data{
                .name = name,
                .function = function,
                .file = file,
                .line = line,
                .color = color,
            };
        }.value;
        return Zone{
            .mContext = tracy.___tracy_emit_zone_begin(src_loc, 1),
        };
    }

    pub fn Deinit(self: Zone) void {
        tracy.___tracy_emit_zone_end(self.mContext);
    }

    /// Attaches runtime text to this zone instance, e.g. the path of the asset being loaded.
    /// Tracy copies the text, so it only has to live for the duration of the call.
    pub fn Text(self: Zone, text: []const u8) void {
        tracy.___tracy_emit_zone_text(self.mContext, text.ptr, text.len);
    }

    /// Replaces this zone instance's name, for zones whose useful name is only known at runtime.
    pub fn Name(self: Zone, name: []const u8) void {
        tracy.___tracy_emit_zone_name(self.mContext, name.ptr, name.len);
    }

    /// Attaches a number to this zone instance, e.g. how many items it processed.
    pub fn Value(self: Zone, value: u64) void {
        tracy.___tracy_emit_zone_value(self.mContext, value);
    }
} else struct {
    pub fn begin(
        comptime _: [*:0]const u8,
        comptime _: ?[*:0]const u8,
        comptime _: [*:0]const u8,
        comptime _: u32,
        comptime _: u32,
    ) Zone {
        return Zone{};
    }

    pub fn Deinit(_: Zone) void {}
    pub fn Text(_: Zone, _: []const u8) void {}
    pub fn Name(_: Zone, _: []const u8) void {}
    pub fn Value(_: Zone, _: u64) void {}
};

pub fn ZoneInit(comptime name: [*:0]const u8, comptime src: std.builtin.SourceLocation) Zone {
    if (enable_tracy) {
        return Zone.begin(
            name,
            src.fn_name, // Optionally use @src().fn_name if available
            src.file.ptr,
            src.line,
            0,
        );
    } else {
        return Zone{};
    }
}

/// The last component of @typeName(T), e.g. "OnUpdateScript" rather than the full module path.
/// Zone source locations are built at compile time, so every instantiation of a generic function
/// shares one zone unless its name says which instantiation it is; this keeps those names short.
pub fn ShortTypeName(comptime T: type) [:0]const u8 {
    const full = @typeName(T);
    const start = if (std.mem.lastIndexOfScalar(u8, full, '.')) |i| i + 1 else 0;
    return full[start..];
}

/// How Tracy labels a plot's values.
pub const PlotFormat = enum(i32) {
    Number = 0,
    /// shown as bytes, KB, MB...
    Memory = 1,
    Percentage = 2,
    Watt = 3,
};

pub const PlotConfig = struct {
    format: PlotFormat = .Number,
    /// true draws a staircase (the value holds until the next sample), false draws lines between samples.
    /// Counts are usually steps, since there is no value in between two frames.
    step: bool = true,
    /// shades the area under the graph
    fill: bool = true,
    /// 0xRRGGBB, 0 lets Tracy pick
    color: u32 = 0,
};

/// Records one sample of a named value over time. Tracy draws every plot as its own graph under the
/// zone timeline, so a spike in a zone can be lined up against what the plotted values did at that moment.
///
/// `name` has to be comptime: Tracy tells plots apart by the address of the name, not its contents, so
/// a name built at runtime would start a new plot every call. `config` is sent to Tracy the first time
/// each plot is sampled.
pub fn Plot(comptime name: [*:0]const u8, comptime config: PlotConfig, value: anytype) void {
    if (enable_tracy) {
        const State = struct {
            var configured: bool = false;
        };
        if (!State.configured) {
            State.configured = true;
            tracy.___tracy_emit_plot_config(name, @intFromEnum(config.format), @intFromBool(config.step), @intFromBool(config.fill), config.color);
        }

        switch (@typeInfo(@TypeOf(value))) {
            .int, .comptime_int => tracy.___tracy_emit_plot_int(name, @intCast(value)),
            .float, .comptime_float => tracy.___tracy_emit_plot(name, @floatCast(value)),
            else => @compileError("Tracy.Plot takes an integer or a float, not " ++ @typeName(@TypeOf(value))),
        }
    }
}

/// The named memory pools Tracy shows allocations under, one per engine allocator.
pub const MemoryPool = enum {
    Engine,
    Frame,
};

/// How many frames of call stack to capture with each memory event, set with -Dtracy-callstack=N.
/// 0 skips capturing. With a depth, Tracy's memory window can show where memory was allocated from,
/// but every allocation then pays for a stack walk.
const callstack_depth: i32 = debug_build_options.tracy_callstack;

// Tracy tells pools apart by the address of the name, so every event for a pool must pass this exact
// pointer; the switch returns the same literal every time.
fn PoolName(comptime pool: MemoryPool) [*:0]const u8 {
    return switch (pool) {
        .Engine => "Engine",
        .Frame => "Frame",
    };
}

/// Reports an allocation. Call it after the memory is handed out.
pub fn MemAlloc(comptime pool: MemoryPool, ptr: *const anyopaque, size: usize) void {
    if (enable_tracy) {
        if (callstack_depth > 0) {
            tracy.___tracy_emit_memory_alloc_callstack_named(ptr, size, callstack_depth, 0, PoolName(pool));
        } else {
            tracy.___tracy_emit_memory_alloc_named(ptr, size, 0, PoolName(pool));
        }
    }
}

/// Reports a free. Call it before the memory is released: once released, another thread can be
/// handed the same address, and Tracy would see that allocation land on memory it thinks is still live.
pub fn MemFree(comptime pool: MemoryPool, ptr: *const anyopaque) void {
    if (enable_tracy) {
        if (callstack_depth > 0) {
            tracy.___tracy_emit_memory_free_callstack_named(ptr, callstack_depth, 0, PoolName(pool));
        } else {
            tracy.___tracy_emit_memory_free_named(ptr, 0, PoolName(pool));
        }
    }
}

/// Marks every allocation still live in `pool` as freed, for allocators like an arena that release
/// everything at once rather than one allocation at a time.
pub fn MemDiscard(comptime pool: MemoryPool) void {
    if (enable_tracy) {
        tracy.___tracy_emit_memory_discard(PoolName(pool), 0);
    }
}

pub fn FrameMark() void {
    if (enable_tracy) {
        tracy.___tracy_emit_frame_mark(null);
    }
}
