const std = @import("std");
const glad = @import("../Core/CImports.zig").glad;
const VertexBufferElement = @import("../VertexBuffers/VertexBufferElement.zig");
const ShaderDataType = @import("Shaders.zig").ShaderDataType;
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
    self.mImpl.SetUniform_Bool(name, value);
}
pub fn SetUniform_Int(self: OpenGLShader, name: []const u8, value: i32) void {
    self.mImpl.SetUniform_Int(name, value);
}
pub fn SetUniform_IntArray(self: OpenGLShader, name: []const u8, value: *i32) void {
    self.mImpl.SetUniform_IntArray(name, value);
}
pub fn SetUniform_Float(self: OpenGLShader, name: []const u8, value: f32) void {
    self.mImpl.SetUniform_Float(name, value);
}
pub fn SetUniform_Vec2(self: OpenGLShader, name: []const u8, value: Vec2f32) void {
    self.mImpl.SetUniform_Vec2(name, value);
}
pub fn SetUniform_Vec3(self: OpenGLShader, name: []const u8, value: Vec3f32) void {
    self.mImpl.SetUniform_Vec3(name, value);
}
pub fn SetUniform_Vec4(self: OpenGLShader, name: []const u8, value: Vec4f32) void {
    self.mImpl.SetUniform_Vec4(name, value);
}
pub fn SetUniform_Mat3(self: OpenGLShader, name: []const u8, value: Mat3f32) void {
    self.mImpl.SetUniform_Mat3(name, value);
}
pub fn SetUniform_Mat4(self: OpenGLShader, name: []const u8, value: Mat4f32) void {
    self.mImpl.SetUniform_Mat4(name, value);
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
fn CreateLayout() void {}
fn DiscoverUniforms() void {}

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
