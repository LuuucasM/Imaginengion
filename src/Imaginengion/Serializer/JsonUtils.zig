const std = @import("std");
const EngineContext = @import("../Core/EngineContext.zig");

/// std.json only hands custom jsonParse functions an allocator. The serializer always parses with
/// EngineContext.Scratch(), whose ptr is the EngineContext itself, so it can be recovered here.
/// Checked against the vtable stored on the context, not &MakeAllocatorVTable(.Scratch).vtable: inside a
/// script DLL that address is the DLL's own copy, while the allocator carries the engine binary's.
pub fn EngineContextFromAllocator(scratch_allocator: std.mem.Allocator) *EngineContext {
    const engine_context: *EngineContext = @ptrCast(@alignCast(scratch_allocator.ptr));
    std.debug.assert(scratch_allocator.vtable == engine_context._Internal.ScratchVTable);
    return engine_context;
}

/// The Keep that what is parsed now goes into: the Keep of the ECS whose component is being read (set by the reader,
/// Serializer.DeserializeContext.keep), the engine's otherwise. `scratch_allocator` is the one parsing is given
pub fn KeepFromAllocator(scratch_allocator: std.mem.Allocator) std.mem.Allocator {
    const engine_context = EngineContextFromAllocator(scratch_allocator);
    return engine_context.mSerializer.mCurrDeserialize.keep orelse engine_context.Keep();
}

/// Generates jsonStringify/jsonParse for a struct from a key -> field mapping, e.g.
///     const Json = JsonUtils.JsonFields(TransformComponent, .{ .Translation = "Translation", .Scale = "Scale" });
///     pub const jsonStringify = Json.jsonStringify;
///     pub const jsonParse = Json.jsonParse;
/// Each field is written with Stringify.write and read with std.json.innerParse, so nested types that define
/// their own jsonStringify/jsonParse (AssetHandle, TexOptions, ...) cascade automatically.
/// std.ArrayList(u8) fields are written as JSON strings and read back into the Keep they belong to (KeepFromAllocator).
/// Keys missing from the JSON keep the struct's default value (T.default if declared, otherwise .{}),
/// and an unknown key is an error.
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

        pub fn jsonParse(scratch_allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!T {
            var result: T = if (@hasDecl(T, "default")) T.default else .{};

            if (.object_begin != try source.next()) return error.UnexpectedToken;

            while (true) {
                const key = switch (try source.nextAllocMax(scratch_allocator, .alloc_if_needed, options.max_value_len.?)) {
                    .object_end => break,
                    inline .string, .allocated_string => |slice| slice,
                    else => return error.UnexpectedToken,
                };

                inline for (keys) |field_key| {
                    if (std.mem.eql(u8, key, field_key)) {
                        const field = &@field(result, @field(fields, field_key));
                        if (@TypeOf(field.*) == std.ArrayList(u8)) {
                            const text = try std.json.innerParse([]const u8, scratch_allocator, source, options);
                            const keep_allocator = KeepFromAllocator(scratch_allocator);
                            field.clearRetainingCapacity();
                            try field.appendSlice(keep_allocator, text);
                        } else {
                            field.* = try std.json.innerParse(@TypeOf(field.*), scratch_allocator, source, options);
                        }
                        break;
                    }
                } else {
                    return error.UnknownField;
                }
            }

            return result;
        }
    };
}
