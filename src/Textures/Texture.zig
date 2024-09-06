const Texture2D = @import("Texture2D.zig");

pub const Texture = union(enum) {
    T_Texture2D: Texture2D,
    pub fn InitData(self: *Texture, width: u32, height: u32, channels: u32, data: *anyopaque, size: usize) void {
        switch (self) {
            inline else => |texture| texture.InitData(width, height, channels, data, size),
        }
    }
    pub fn InitPath(self: *Texture, path: []const u8) void {
        switch (self) {
            inline else => |texture| texture.InitPath(path),
        }
    }
    pub fn Deinit(self: Texture) void {
        switch (self) {
            inline else => |texture| texture.Deinit(),
        }
    }
    pub fn GetWidth(self: Texture) u32 {
        switch (self) {
            inline else => |texture| return texture.GetWidth(),
        }
    }
    pub fn GetHeight(self: Texture) u32 {
        switch (self) {
            inline else => |texture| return texture.GetHeight(),
        }
    }
    pub fn GetID(self: Texture) u32 {
        switch (self) {
            inline else => |texture| return texture.GetID(),
        }
    }
    pub fn UpdateData(self: *Texture, width: u32, height: u32, data: *anyopaque, size: usize) void {
        switch (self) {
            inline else => |texture| texture.UpdateData(width, height, data, size),
        }
    }
    pub fn UpdateDataPath(self: *Texture, path: []const u8) void {
        switch (self.*) {
            inline else => |*texture| texture.UpdateDataPath(path),
        }
    }
    pub fn Bind(self: Texture, slot: u32) void {
        switch (self) {
            inline else => |texture| texture.Bind(slot),
        }
    }
    pub fn Unbind(self: Texture, slot: u32) void {
        switch (self) {
            inline else => |texture| texture.Unbind(slot),
        }
    }
};
