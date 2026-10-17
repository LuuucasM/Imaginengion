const ListInd = @import("../ECS/Components.zig").ListInd;
pub const AttribComponent = @import("Shared/AttribComponent.zig");
pub const EnumComponent = @import("Shared/EnumComponent.zig");
pub const AudioComponent = @import("Shared/AudioComponent.zig");
pub const NameComponent = @import("Shared/NameComponent.zig");
pub const UUIDComponent = @import("Shared/UUIDComponent.zig");
pub const ScriptComponent = @import("Shared/ScriptComponent.zig");
pub const TmplRefComponent = @import("Shared/TmplRefComponent.zig");
const This = @This();

const ScriptTags = @import("Shared/ScriptTags.zig");
pub const OnGameStartScript = ScriptTags.OnGameStartScript;
pub const OnUpdateScript = ScriptTags.GameContextOnUpdateScript;
pub const UntypedScriptTag = ScriptTags.UntypedScriptTag;
pub const GameEventScript = ScriptTags.GameEventScript;

pub const ComponentsList = [_]type{
    AttribComponent,
    EnumComponent,
    AudioComponent,
    NameComponent,
    UUIDComponent,
    ScriptComponent,
    TmplRefComponent,

    //Scripts
    OnGameStartScript,
    OnUpdateScript,
    UntypedScriptTag,
    GameEventScript,
};

pub const ComponentsPanelList = [_]type{
    AttribComponent,
    EnumComponent,
    AudioComponent,
    NameComponent,
    UUIDComponent,
    TmplRefComponent,
};

/// ScriptComponent is not listed, scripts are saved separately and recreated with AddScript
pub const SerializeList = [_]type{
    UUIDComponent,
    NameComponent,
    AttribComponent,
    EnumComponent,
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
    OnGameStartScript,
    OnUpdateScript,
};

pub const EComponents = enum(u16) {
    AttribComponent = ListInd(&ComponentsList, AttribComponent),
    EnumComponent = ListInd(&ComponentsList, EnumComponent),
    AudioComponent = ListInd(&ComponentsList, AudioComponent),
    NameComponent = ListInd(&ComponentsList, NameComponent),
    UUIDComponent = ListInd(&ComponentsList, UUIDComponent),
    TmplRefComponent = ListInd(&ComponentsList, TmplRefComponent),
    ScriptComponent = ListInd(&ComponentsList, ScriptComponent),
    OnGameStartScript = ListInd(&ComponentsList, OnGameStartScript),
    OnUpdateScript = ListInd(&ComponentsList, OnUpdateScript),
    UntypedScriptTag = ListInd(&ComponentsList, UntypedScriptTag),
    GameEventScript = ListInd(&ComponentsList, GameEventScript),
};
