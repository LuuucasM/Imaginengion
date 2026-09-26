const ListInd = @import("../ECS/Components.zig").ListInd;
pub const VoiceComponent = @import("Voice/VoiceComponent.zig");
pub const VoiceAssetComponent = @import("Voice/VoiceAssetComponent.zig");
pub const VoiceVolumeComponent = @import("Voice/VoiceVolumeComponent.zig");

/// Voices are never saved or edited, so there is no SerializeList or ComponentsPanelList
pub const ComponentsList = [_]type{
    VoiceComponent,
    VoiceAssetComponent,
    VoiceVolumeComponent,
};

pub const EComponents = enum(u16) {
    VoiceComponent = ListInd(&ComponentsList, VoiceComponent),
    VoiceAssetComponent = ListInd(&ComponentsList, VoiceAssetComponent),
    VoiceVolumeComponent = ListInd(&ComponentsList, VoiceVolumeComponent),
};
