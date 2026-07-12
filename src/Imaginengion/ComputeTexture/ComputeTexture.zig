const builtin = @import("builtin");
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const EngineContext = @import("../Core/EngineContext.zig");

pub fn ComputeStorageTexture(comptime format: TextureFormat) type {
    return struct {
        const Self = @This();
        const Impl = switch (builtin.os.tag) {
            .windows => @import("SDLComputeTexture.zig").SDLComputeStorageTexture,
            else => @compileError("Not supported yet"),
        };
        const ImplType = Impl(format);

        _Impl: ImplType,

        pub const empty: Self = .{
            ._Impl = .empty,
        };

        pub fn Init(self: *Self, engine_context: *EngineContext, width: usize, height: usize) !void {
            self._Impl.Init(engine_context, width, height);
        }

        pub fn Deinit(self: *Self, engine_context: *EngineContext) !void {
            self._Impl.Deinit(engine_context);
        }

        pub fn Resize(self: *Self, engine_context: *EngineContext, width: usize, height: usize) !void {
            self._Impl.Resize(engine_context, width, height);
        }

        pub fn Invalidate(self: *Self, engine_context: *EngineContext) !void {
            self._Impl.Invalidate(engine_context);
        }

        pub fn BeginComputePass(self: *Self, engine_context: *EngineContext, cycle: bool) *anyopaque {
            self._Impl.BeginComputePass(engine_context, cycle);
        }

        pub fn EndComputePass(self: Self, pass: *anyopaque) void {
            self._Impl.EndComputePass(pass);
        }

        pub fn BindSampler(self: Self, render_pass: *anyopaque, slot: u32) void {
            self._Impl.BindSampler(render_pass, slot);
        }

        pub fn GetTexture(self: Self) *anyopaque {
            self._Impl.GetTexture();
        }

        pub fn GetWidth(self: Self) usize {
            self._Impl.GetWidth();
        }

        pub fn GetHeight(self: Self) usize {
            self._Impl.GetHeight();
        }
    };
}
