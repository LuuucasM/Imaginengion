const ListInd = @import("../ECS/Components.zig").ListInd;
pub const VoiceComponent = @import("Voice/VoiceComponent.zig");
pub const VoiceAssetComponent = @import("Voice/VoiceAssetComponent.zig");
pub const VoiceVolumeComponent = @import("Voice/VoiceVolumeComponent.zig");
pub const VoicePitchComponent = @import("Voice/VoicePitchComponent.zig");
pub const VoiceFadeComponent = @import("Voice/VoiceFadeComponent.zig");

/// Voices are never saved or edited, so there is no SerializeList or ComponentsPanelList
pub const ComponentsList = [_]type{
    VoiceComponent,
    VoiceAssetComponent,
    VoiceVolumeComponent,
    VoicePitchComponent,
    VoiceFadeComponent,
};

pub const EComponents = enum(u16) {
    VoiceComponent = ListInd(&ComponentsList, VoiceComponent),
    VoiceAssetComponent = ListInd(&ComponentsList, VoiceAssetComponent),
    VoiceVolumeComponent = ListInd(&ComponentsList, VoiceVolumeComponent),
    VoicePitchComponent = ListInd(&ComponentsList, VoicePitchComponent),
    VoiceFadeComponent = ListInd(&ComponentsList, VoiceFadeComponent),
};
