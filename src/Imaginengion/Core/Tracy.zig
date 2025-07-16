const std = @import("std");
const tracy = @import("CImports.zig").tracy;

pub const Zone = struct {
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
};

/// Macro-like helper for easy zone usage. Example:
///   const zone = Tracy.zoneScoped("Main Loop");
///   defer zone.end();
pub inline fn ZoneInit(comptime name: [*:0]const u8, comptime src: std.builtin.SourceLocation) Zone {
    return Zone.begin(
        name,
        src.fn_name, // Optionally use @src().fn_name if available
        src.file.ptr,
        src.line,
        0,
    );
}

pub fn FrameMark() void {
    tracy.___tracy_emit_frame_mark(null);
}
