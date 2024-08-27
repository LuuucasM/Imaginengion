const Texture2D = @import("Texture2D.zig");

const Texture = union {
    T_Texture2D: Texture2D,
    pub fn InitSize(self: Texture, width: u32, height: u32) void {
        switch(self){
            inline else => |texture| texture.InitSize(width, height);
        }
    }
    pub fn InitPath(self: Texture, path: []const u8) void {
        switch(self) {
            inline else => |texture| texture.InitPath(path);
        }
    }
    pub fn Deinit(self: Texture) void {
        switch(self) {
            inline else => |texture| texture.Deinit();
        }
    }
    pub fn GetWidth(self: Texture) u32 {
        switch(self) {
            inline else => |texture| return texture.GetWidth();
        }
    }
    pub fn GetHeight(self: Texture) u32 {
        switch(self){
            inline else => |texture| return texture.GetHeight();
        }
    }
    pub fn GetID(self: Texture) u32 {
        switch(self){
            inline else => |texture| return texture.GetID();
        }
    }
    pub fn SetData(self: Texture, data: *anyopaque) void {
        switch(self){
            inline else => |texture| texture.SetData(data);
        }
    }
    pub fn Bind(self: Texture) void {
        switch(self){
            inline else => |texture| texture.Bind();
        }
    }
    pub fn Unbind(self: Texture) void {
        switch(self){
            inline else => |texture| texture.Unbind();
        }
    }
};
