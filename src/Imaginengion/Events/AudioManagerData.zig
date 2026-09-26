const Voice = @import("../ECSObjects/Voice.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    DestroyVoice: DestroyVoiceEvent,

    pub const DefaultEvent = struct {};

    pub const DestroyVoiceEvent = struct {
        Voice: Voice,
    };
};
