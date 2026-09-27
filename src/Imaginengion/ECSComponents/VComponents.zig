const ListInd = @import("../ECS/Components.zig").ListInd;
pub const VoiceComponent = @import("Voice/VoiceComponent.zig");
pub const VoiceAssetComponent = @import("Voice/VoiceAssetComponent.zig");
pub const VoicePitchComponent = @import("Voice/VoicePitchComponent.zig");
pub const VoiceFadeComponent = @import("Voice/VoiceFadeComponent.zig");
pub const BusComponent = @import("Bus/BusComponent.zig");
pub const VolumeComponent = @import("Shared/VolumeComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");

/// The components of the AudioManager's objects, its voices and its buses, which share the one ECS
pub const ComponentsList = [_]type{
    VoiceComponent,
    VoiceAssetComponent,
    VoicePitchComponent,
    VoiceFadeComponent,
    BusComponent,
    VolumeComponent,
    NameComponent,
    UUIDComponent,
};

/// What a bus is saved with, as part of the project's audio settings. Voices are never saved. BusComponent is left
/// out: whether a bus is paused and its current gain are how it is playing right now, and every bus gets a fresh one
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    VolumeComponent,
};

pub const EComponents = enum(u16) {
    VoiceComponent = ListInd(&ComponentsList, VoiceComponent),
    VoiceAssetComponent = ListInd(&ComponentsList, VoiceAssetComponent),
    VoicePitchComponent = ListInd(&ComponentsList, VoicePitchComponent),
    VoiceFadeComponent = ListInd(&ComponentsList, VoiceFadeComponent),
    BusComponent = ListInd(&ComponentsList, BusComponent),
    VolumeComponent = ListInd(&ComponentsList, VolumeComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
};
