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
        offset = padded_offset + gpuSize(field_type);
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

//Zig's SPIR-V backend sizes a 3 element vector as 16 bytes, not std430's 12, so a scalar placed
//straight after one lands 4 bytes later on the GPU than a [3]f32 puts it on the CPU
fn gpuSize(comptime T: type) usize {
    return switch (@typeInfo(T)) {
        .vector => |v| if (v.len == 3) 16 else @sizeOf(T),
        .array => |a| if (a.len == 3) 16 else @sizeOf(T),
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
