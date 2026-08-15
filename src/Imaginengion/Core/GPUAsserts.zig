const std = @import("std");
pub fn AssertGPULayout(comptime T: type) void {
    const info = @typeInfo(T).@"struct";
    comptime var offset: usize = 0;

    inline for (info.field_types, info.field_names) |field_type, field_name| {
        const align_req = gpuAlign(field_type);
        const padded_offset = std.mem.alignForward(usize, offset, align_req);

        if (@offsetOf(T, field_name) != padded_offset) {
            @compileError(std.fmt.comptimePrint(
                "{s}.{s}: offset {d} != expected {d} (align {d})",
                .{ @typeName(T), field_name, @offsetOf(T, field_name), padded_offset, align_req },
            ));
        }
        offset = padded_offset + @sizeOf(field_type);
    }

    const base_align = gpuBaseAlign(T);
    const total = std.mem.alignForward(usize, offset, base_align);
    if (@sizeOf(T) != total) {
        @compileError(std.fmt.comptimePrint(
            "{s}: size {d} != expected {d} (struct align {d})",
            .{ @typeName(T), @sizeOf(T), total, base_align },
        ));
    }
}

fn gpuAlign(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .vector => |v| vecAlign(v.len),
        .array => |a| vecAlign(a.len),
        .@"struct" => 16,
        else => @sizeOf(T),
    };
}

fn vecAlign(len: usize) usize {
    return switch (len) {
        1 => 4,
        2 => 8,
        3, 4 => 16,
        else => @compileError("bad vec len"),
    };
}

fn gpuBaseAlign(comptime T: type) usize {
    comptime var max: usize = 4;
    inline for (@typeInfo(T).@"struct".field_types) |f| {
        const a = gpuAlign(f);
        if (a > max) max = a;
    }
    return max;
}
