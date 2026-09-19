const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");
const MakeAllocatorVTable = @import("../Core/Allocators.zig").MakeAllocatorVTable;

/// std.json only hands custom jsonParse functions an allocator. The serializer always parses with
/// EngineContext.FrameAllocator(), whose ptr is the EngineContext itself, so it can be recovered here.
pub fn EngineContextFromAllocator(frame_allocator: std.mem.Allocator) *EngineContext {
    std.debug.assert(frame_allocator.vtable == &MakeAllocatorVTable(.Frame).vtable);
    return @ptrCast(@alignCast(frame_allocator.ptr));
}

/// Generates jsonStringify/jsonParse for a struct from a key -> field mapping, e.g.
///     const Json = JsonUtils.JsonFields(TransformComponent, .{ .Translation = "Translation", .Scale = "Scale" });
///     pub const jsonStringify = Json.jsonStringify;
///     pub const jsonParse = Json.jsonParse;
/// Each field is written with Stringify.write and read with std.json.innerParse, so nested types that define
/// their own jsonStringify/jsonParse (AssetHandle, TexOptions, ...) cascade automatically.
/// std.ArrayList(u8) fields are written as JSON strings and read back into the engine allocator.
/// Keys missing from the JSON keep the struct's default value (T.default if declared, otherwise .{}),
/// and unknown keys are skipped so old files keep loading after fields are removed.
pub fn JsonFields(comptime T: type, comptime fields: anytype) type {
    const keys = @typeInfo(@TypeOf(fields)).@"struct".field_names;
    comptime {
        for (keys) |key| {
            if (!@hasField(T, @field(fields, key))) {
                @compileError(std.fmt.comptimePrint("JsonFields: {s} has no field '{s}' (json key '{s}')", .{ @typeName(T), @field(fields, key), key }));
            }
        }
    }

    return struct {
        pub fn jsonStringify(self: *const T, jw: anytype) !void {
            try jw.beginObject();
            inline for (keys) |key| {
                const value = @field(self, @field(fields, key));
                try jw.objectField(key);
                if (@TypeOf(value) == std.ArrayList(u8)) {
                    try jw.write(value.items);
                } else {
                    try jw.write(value);
                }
            }
            try jw.endObject();
        }

        pub fn jsonParse(frame_allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            var result: T = if (@hasDecl(T, "default")) T.default else .{};

            if (.object_begin != try source.next()) return error.UnexpectedToken;

            while (true) {
                const key = switch (try source.nextAllocMax(frame_allocator, .alloc_if_needed, options.max_value_len.?)) {
                    .object_end => break,
                    inline .string, .allocated_string => |slice| slice,
                    else => return error.UnexpectedToken,
                };

                inline for (keys) |field_key| {
                    if (std.mem.eql(u8, key, field_key)) {
                        const field = &@field(result, @field(fields, field_key));
                        if (@TypeOf(field.*) == std.ArrayList(u8)) {
                            const text = try std.json.innerParse([]const u8, frame_allocator, source, options);
                            const engine_allocator = EngineContextFromAllocator(frame_allocator).EngineAllocator();
                            field.clearRetainingCapacity();
                            try field.appendSlice(engine_allocator, text);
                        } else {
                            field.* = try std.json.innerParse(@TypeOf(field.*), frame_allocator, source, options);
                        }
                        break;
                    }
                } else {
                    try source.skipValue();
                }
            }

            return result;
        }
    };
}
