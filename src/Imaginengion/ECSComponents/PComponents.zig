const ListInd = @import("../ECS/Components.zig").ListInd;
pub const AttribComponent = @import("Shared/AttribComponent.zig");
pub const AudioComponent = @import("Shared/AudioComponent.zig");
pub const RenderTargetComponent = @import("Shared/RenderTargetComponent.zig");
pub const MicComponent = @import("Player/MicComponent.zig");
pub const PossessComponent = @import("Player/PossessComponent.zig");
pub const OverlayComponent = @import("Player/OverlayComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");

const ScriptTags = @import("Shared/ScriptTags.zig");
pub const OnUpdateScript = ScriptTags.PlayerOnUpdateScript;
pub const OnInputPressedScript = ScriptTags.PlayerOnInputPressedScript;
pub const UntypedScriptTag = ScriptTags.UntypedScriptTag;
pub const GameEventScript = ScriptTags.GameEventScript;

pub const ComponentsList = [_]type{
    AttribComponent,
    AudioComponent,
    RenderTargetComponent,
    MicComponent,
    PossessComponent,
    OverlayComponent,
    NameComponent,
    UUIDComponent,
    ScriptComponent,
    TmplRefComponent,

    //Scripts
    OnUpdateScript,
    OnInputPressedScript,
    UntypedScriptTag,
    GameEventScript,
};

pub const ComponentsPanelList = [_]type{
    UUIDComponent,
    NameComponent,
    AttribComponent,
    PossessComponent,
    OverlayComponent,
    MicComponent,
    AudioComponent,
    RenderTargetComponent,
    TmplRefComponent,
};

/// ScriptComponent is not listed, scripts are saved separately and recreated with AddScript
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    AttribComponent,
    RenderTargetComponent,
    MicComponent,
    PossessComponent,
    OverlayComponent,
    AudioComponent,
    TmplRefComponent,
};

/// What a linked copy keeps of its own when it is stripped down (see ECSObject.Core.Strip), everything
/// else in SerializeList it gets from its template
pub const ShellList = [_]type{
    UUIDComponent,
    NameComponent,
    TmplRefComponent,
};

pub const ScriptsList = [_]type{
    OnUpdateScript,
    OnInputPressedScript,
};

pub const EComponents = enum(u16) {
    AttribComponent = ListInd(&ComponentsList, AttribComponent),
    AudioComponent = ListInd(&ComponentsList, AudioComponent),
    RenderTargetComponent = ListInd(&ComponentsList, RenderTargetComponent),
    MicComponent = ListInd(&ComponentsList, MicComponent),
    PossessComponent = ListInd(&ComponentsList, PossessComponent),
    OverlayComponent = ListInd(&ComponentsList, OverlayComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),
    ScriptComponent = ListInd(&ComponentsList, ScriptComponent),
    OnUpdateScript = ListInd(&ComponentsList, OnUpdateScript),
    OnInputPressedScript = ListInd(&ComponentsList, OnInputPressedScript),
    UntypedScriptTag = ListInd(&ComponentsList, UntypedScriptTag),
    GameEventScript = ListInd(&ComponentsList, GameEventScript),
};
