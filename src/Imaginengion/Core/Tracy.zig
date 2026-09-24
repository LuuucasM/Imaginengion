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

pub fn FrameMark() void {
    if (enable_tracy) {
        tracy.___tracy_emit_frame_mark(null);
    }
}
