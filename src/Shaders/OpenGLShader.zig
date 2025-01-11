const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const VertexBufferElement = @import("../VertexBuffers/VertexBufferElement.zig");
const ShaderDataType = @import("Shaders.zig").ShaderDataType;
const ShaderDataTypeSize = @import("Shaders.zig").ShaderDataTypeSize;
const LinAlg = @import("../Math/LinAlg.zig");
const Vec2f32 = LinAlg.Vec2f32;
const Vec3f32 = LinAlg.Vec3f32;
const Vec4f32 = LinAlg.Vec4f32;
const Mat3f32 = LinAlg.Mat3f32;
const Mat4f32 = LinAlg.Mat4f32;

const OpenGLShader = @This();

mBufferElements: std.ArrayList(VertexBufferElement),
mUniforms: std.AutoHashMap(u32, i32),
mBufferStride: u32,
mShaderID: u32,
mName: []const u8,
mAllocator: std.mem.Allocator,

pub fn Init(allocator: std.mem.Allocator, abs_path: []const u8) OpenGLShader {
    const new_shader = OpenGLShader{
        .mBufferElements = std.ArrayList(VertexBufferElement).init(allocator),
        .mUniforms = std.AutoHashMap(u32, i32).init(allocator),
        .mBufferStride = 0,
        .mShaderID = 0,
        .mName = undefined,
        .mAllocator = allocator,
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const shader_sources = try ReadFile(abs_path, arena.allocator());
    if (Compile(&new_shader.mShaderID, shader_sources) == true) {
        CreateLayout(shader_sources.get(glad.GL_VERTEX_SHADER).?);
        DiscoverUniforms();
    }

    new_shader.mName = new_shader.mAllocator.dupe(u8, std.fs.path.basename(abs_path));

    return new_shader;
}

pub fn Deinit(self: OpenGLShader) void {
    glad.glDeleteShader(self.mShaderID);

    self.mBufferElements.deinit();
    self.mUniforms.deinit();
    self.mAllocator.free(self.mName);
}

pub fn Bind(self: OpenGLShader) void {
    glad.glUseProgram(self.mShaderID);
}

pub fn Unbind(self: OpenGLShader) void {
    _ = self;
    glad.glUseProgram(0);
}

pub fn SetUniform_Bool(self: OpenGLShader, name: []const u8, value: bool) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform1i(self.mUniforms.get(hash_val).?, @intFromBool(value));
}
pub fn SetUniform_Int(self: OpenGLShader, name: []const u8, value: i32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform1i(self.mUniforms.get(hash_val).?, value);
}
pub fn SetUniform_IntArray(self: OpenGLShader, name: []const u8, value: *i32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform1iv(self.mUniforms.get(hash_val).?, value);
}
pub fn SetUniform_Float(self: OpenGLShader, name: []const u8, value: f32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform1f(self.mUniforms.get(hash_val).?, value);
}
pub fn SetUniform_Vec2(self: OpenGLShader, name: []const u8, value: Vec2f32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform2f(self.mUniforms.get(hash_val).?, value[0], value[1]);
}
pub fn SetUniform_Vec3(self: OpenGLShader, name: []const u8, value: Vec3f32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform3f(self.mUniforms.get(hash_val).?, value[0], value[1], value[2]);
}
pub fn SetUniform_Vec4(self: OpenGLShader, name: []const u8, value: Vec4f32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniform4f(self.mUniforms.get(hash_val).?, value[0], value[1], value[2], value[3]);
}
pub fn SetUniform_Mat3(self: OpenGLShader, name: []const u8, value: Mat3f32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniformMatrix3fv(self.mUniforms.get(hash_val).?, 1, glad.GL_FALSE, &value);
}
pub fn SetUniform_Mat4(self: OpenGLShader, name: []const u8, value: Mat4f32) void {
    var hasher = std.hash.Fnv1a_32.init();
    hasher.update(name);
    const hash_val = hasher.final();
    std.debug.assert(self.mUniforms.contains(hash_val));

    glad.glUniformMatrix4fv(self.mUniforms.get(hash_val).?, 1, glad.GL_FALSE, &value);
}

fn CreateLayout(self: OpenGLShader, shader_source: []const u8) void {
    // Split shader into lines
    var lines = std.mem.split(u8, shader_source, "\n");

    while (lines.next()) |line| {
        // Trim whitespace
        const trimmed = std.mem.trim(u8, line, " \t");

        // Check if line starts with layout
        if (std.mem.startsWith(u8, trimmed, "layout")) {
            // Find the "in" keyword after layout declaration
            if (std.mem.indexOf(u8, trimmed, ") in ")) |in_pos| {
                // Extract everything after "in" keyword
                const after_in = trimmed[in_pos + 5 ..];

                // Split by spaces to get type and variable name
                var tokens = std.mem.split(u8, after_in, " ");
                if (tokens.next()) |type_str| {
                    // Convert type string to ShaderDataType
                    const data_type = TypeStrToDataType(type_str);
                    self.mBufferElements.append(.{ .mType = data_type, .mSize = ShaderDataTypeSize(data_type), .mOffset = 0, .mIsNormalized = false });
                }
            }
        }
    }
    self.CalculateOffsets();
    self.CalculateStride();
}
fn DiscoverUniforms(self: OpenGLShader) void {
    var i: glad.GLint = undefined;
    var count: glad.GLint = undefined;
    var size: glad.GLint = undefined;
    var data_type: glad.GLenum = undefined;
    var length: glad.glsizei = undefined;
    const uniname: [32]u8 = undefined;

    glad.glGetProgramiv(self.mShaderID, glad.GL_ACTIVE_UNIFORMS, &count);

    while (i < count) : (i += 1) {
        glad.glGetActiveUniform(self.mShaderID, i, 32, &length, &size, &data_type, uniname);

        const name_slice = uniname[0..length];

        var final_name: []const u8 = undefined;
        if (std.mem.indexOf(u8, name_slice, "[")) |found| {
            final_name = name_slice[0..found];
        } else {
            final_name = name_slice;
        }

        const location = glad.glGetUniformLocation(self.mShaderID, final_name.ptr);

        var hasher = std.hash.Fnv1a_32.init();
        hasher.update(final_name);

        self.mUniforms.put(hasher.final(), location);
    }
}
fn CalculateOffsets(self: OpenGLShader) void {
    var offset: u32 = 0;
    for (self.mBufferElements) |element| {
        element.mOffset = offset;
        offset += element.mSize;
    }
}
fn CalculateStride(self: OpenGLShader) void {
    self.mBufferStride = 0;
    for (self.mBufferElements) |element| {
        self.mBufferStride += element.mSize;
    }
}

fn ReadFile(allocator: std.mem.Allocator, source: []const u8) !std.AutoArrayHashMap(u32, []const u8) {
    var shaders = std.AutoArrayHashMap(u32, []const u8).init(allocator);
    errdefer {
        var iter = shaders.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        shaders.deinit();
    }

    var lines = std.mem.split(u8, source, "\n");
    var current_type: c_uint = undefined;
    var has_type = false;
    var current_source = std.ArrayList(u8).init(allocator);
    defer current_source.deinit();

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed, "#type")) {
            // If we have accumulated source code, save it
            if (current_source.items.len > 0 and has_type) {
                try shaders.put(
                    current_type,
                    try allocator.dupeZ(u8, current_source.items),
                );
                current_source.clearRetainingCapacity();
            }

            // Parse the shader type
            const type_str = std.mem.trim(u8, trimmed[5..], " \t\r\n");
            current_type = ShaderTypeFromStr(type_str);
            has_type = true;
        } else if (has_type) {
            // Add the current line to the source code
            try current_source.appendSlice(line);
            try current_source.append('\n');
        }
    }

    // Don't forget to save the last shader section
    if (current_source.items.len > 0 and has_type) {
        try shaders.put(
            current_type,
            try allocator.dupeZ(u8, current_source.items),
        );
    }

    return shaders;
}

fn Compile(shader_id_out: *u32, shader_sources: std.AutoArrayHashMap(u32, []const u8)) void {
    const shader_id: glad.GLuint = glad.glCreateProgram();

    var buffer: [40 + 256]u8 = undefined;
    const fba = std.heap.FixedBufferAllocator(&buffer);
    const gl_shader_ids = std.ArrayList(glad.GLenum).init(fba.allocator);

    var iter = shader_sources.iterator();
    while (iter.next()) |entry| {
        const shader_type = entry.key_ptr.*;
        const shader_source = entry.value_ptr.*;

        const shader = glad.glCreateShader(shader_type);

        glad.glShaderSource(shader, 1, shader_source.ptr, 0);

        glad.glCompileShader(shader);

        var is_compiled: glad.GLint = 0;
        glad.glGetShaderiv(shader, glad.GL_COMPILE_STATUS, &is_compiled);
        if (is_compiled == glad.GL_FALSE) {
            const max_length: glad.GLint = 0;
            glad.glGetShaderiv(shader, glad.GL_INFO_LOG_LENGTH, &max_length);

            const info_log = try std.ArrayList(u8).initCapacity(fba.allocator, max_length);
            glad.glGetShaderInfoLog(shader, max_length, &max_length, info_log.items.ptr);

            glad.glDeleteShader(shader);

            std.log.err("Shader Compilation Failure! {s}\n", .{info_log.items});

            return false;
        }
        glad.glAttachShader(shader_id, shader);
        gl_shader_ids.append(shader);
    }

    shader_id_out.* = shader_id;

    glad.glLinkProgram(shader_id);

    const is_linked: glad.GLint = 0;
    glad.glGetProgramiv(shader_id, glad.GL_LINK_STATUS, &is_linked);
    if (is_linked == glad.GL_FALSE) {
        const max_length: glad.GLint = 0;
        glad.glGetProgramiv(shader_id, glad.GL_INFO_LOG_LENGTH, &max_length);

        const info_log = try std.ArrayList(u8).initCapacity(fba.allocator, max_length);
        glad.glGetProgramInfoLog(shader_id, max_length, &max_length, info_log.items.ptr);

        glad.glDeleteProgram(shader_id);

        for (gl_shader_ids) |id| {
            glad.glDeleteShader(id);
        }

        std.log.err("Program failed to link! {s}\n", .{info_log.items});

        return false;
    }
    for (gl_shader_ids) |id| {
        glad.glDetachShader(shader_id, id);
        glad.glDeleteShader(id);
    }
    return true;
}

fn ShaderTypeFromStr(str: []const u8) glad.GLenum {
    if (std.mem.eql(u8, str, "vertex") == true) {
        return glad.GL_VERTEX_SHADER;
    } else if (std.mem.eql(u8, str, "fragment") == true) {
        return glad.GL_FRAGMENT_SHADER;
    } else {
        @panic("Unkown shader type!\n");
    }
}

fn TypeStrToDataType(str: []const u8) ShaderDataType {
    if (std.mem.eql(u8, str, "float")) return ShaderDataType.Float else if (std.mem.eql(u8, str, "vec2")) return ShaderDataType.Float2 else if (std.mem.eql(u8, str, "vec3")) return ShaderDataType.Float3 else if (std.mem.eql(u8, str, "vec4")) return ShaderDataType.Float4 else if (std.mem.eql(u8, str, "mat3")) return ShaderDataType.Mat3 else if (std.mem.eql(u8, str, "mat4")) return ShaderDataType.Mat4 else if (std.mem.eql(u8, str, "uint")) return ShaderDataType.UInt else if (std.mem.eql(u8, str, "int")) return ShaderDataType.Int else if (std.mem.eql(u8, str, "int2")) return ShaderDataType.Int2 else if (std.mem.eql(u8, str, "int3")) return ShaderDataType.Int3 else if (std.mem.eql(u8, str, "int4")) return ShaderDataType.Int4 else if (std.mem.eql(u8, str, "bool")) return ShaderDataType.Bool;
}
