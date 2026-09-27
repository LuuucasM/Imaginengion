const Voice = @import("../ECSObjects/Voice.zig");
const Bus = @import("../ECSObjects/Bus.zig");

pub const EventCategories = enum(u8) {
    EndOfFrame,
};

pub const EventT = union(enum) {
    Default: DefaultEvent,
    DestroyVoice: DestroyVoiceEvent,
    DestroyBus: DestroyBusEvent,

    pub const DefaultEvent = struct {};

    pub const DestroyVoiceEvent = struct {
        Voice: Voice,
    };

    pub const DestroyBusEvent = struct {
        Bus: Bus,
    };
};
