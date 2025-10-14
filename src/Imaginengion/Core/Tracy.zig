const std = @import("std");
const build_options = @import("build_options");

pub const enable_tracy = build_options.enable_tracy;

const tracy = if (enable_tracy) @import("CImports.zig").tracy else void;

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
            .mContext = tracy.___tracy_emit_zone_begin_callstack(src_loc, 1, 1),
        };
    }

    pub fn Deinit(self: Zone) void {
        tracy.___tracy_emit_zone_end(self.mContext);
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

pub fn FrameMark() void {
    if (enable_tracy) {
        tracy.___tracy_emit_frame_mark(null);
    }
}
