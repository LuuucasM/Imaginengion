const ma = @import("../Core/CImports.zig").miniaudio;
const MiniAudioContext = @This();

mEngine: ma.ma_engine = undefined,

pub fn Init() !MiniAudioContext {
    return MiniAudioContext{};
}

pub fn Setup(self: *MiniAudioContext) !void {
    const engine_config = ma.ma_engine_config_init();
    const engine_result = ma.ma_engine_init(&engine_config, &self.mEngine);
    if (engine_result == ma.MA_ERROR) return error.EngineInitFail;
}

pub fn Deinit(self: *MiniAudioContext) MiniAudioContext {
    ma.ma_engine_uinit(&self.mEngine);
}
