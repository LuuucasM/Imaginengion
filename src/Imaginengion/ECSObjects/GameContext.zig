const std = @import("std");
pub const Type = u32;
pub const NullObject: Type = std.math.maxInt(Type);

const EngineContext = @import("../Core/EngineContext.zig");
const WorldManager = @import("../Core/WorldManager.zig");
const GameModeParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const GameModeChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const GameModeComponents = @import("../ECSComponents/GCComponents.zig");
const UUIDComponent = GameModeComponents.UUIDComponent;
const NameComponent = GameModeComponents.NameComponent;
const ScriptComponent = GameModeComponents.ScriptComponent;
const PathType = @import("../ECSManagers/AManager.zig").PathType;
const ScriptAsset = @import("../ECSComponents/AComponents.zig").ScriptAsset;
const GameContext = @This();
const ECSCore = @import("ECSObject.zig").Core;
const AssetHandle = @import("AssetHandle.zig");

const Core = ECSCore(GameContext);

pub const CreateConfig = struct {
    bAddUUIDComponent: bool,
    bAddNameComponent: bool,
};

pub const DefaultConfig: CreateConfig = .{
    .bAddUUIDComponent = true,
    .bAddNameComponent = true,
};

/// Nothing added, for objects whose components all come from somewhere else (e.g. a file)
pub const BlankConfig: CreateConfig = .{
    .bAddUUIDComponent = false,
    .bAddNameComponent = false,
};

/// A script child (see Core.AddScript): no UUID, nothing looks one up and it is saved as its ScriptComponent alone
pub const ScriptConfig: CreateConfig = .{
    .bAddUUIDComponent = false,
    .bAddNameComponent = true,
};

pub const uninit: GameContext = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *WorldManager,

pub const AddComponent = Core.AddComponent;

pub const RemoveComponent = Core.RemoveComponent;
pub const RemoveComponentSync = Core.RemoveComponentSync;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetName = Core.GetName;
pub const SetName = Core.SetName;

pub const PlayAudio = Core.PlayAudio;
pub const StopAudio = Core.StopAudio;

pub const Duplicate = Core.Duplicate;

pub const GetUUID = Core.GetUUID;

pub const GetWorld = Core.GetWorld;

pub const Delete = Core.Delete;

pub const SetTmpl = Core.SetTmpl;

pub const Fill = Core.Fill;

pub const Strip = Core.Strip;

pub const MakeTmpl = Core.MakeTmpl;

pub const GetIterator = Core.GetIterator;

pub const IsActive = Core.IsActive;

pub const IsIDValid = Core.IsIDValid;

pub const Invalidate = Core.Invalidate;

pub const CreateChild = Core.CreateChild;

pub fn AddScript(self: GameContext, engine_context: *EngineContext, new_script_handle: AssetHandle) !void {
    const script_asset = new_script_handle.GetAsset(engine_context, ScriptAsset) catch |err| switch (err) {
        //it failed to load (the reason is already logged). Keep the script child so the script stays on the game
        //context and is saved back out. Nothing runs it until its file is fixed, see ScriptsProcessor.SyncScriptTypes
        error.NoDefaultAsset => {
            const new_script_context = try Core.AddScript(self, engine_context, new_script_handle);
            _ = try new_script_context.AddComponent(engine_context, GameModeComponents.UntypedScriptTag{});
            return;
        },
        else => return err,
    };
    const script_type = script_asset.GetScriptType();
    _ValidateScriptType(script_type);

    const new_script_context = try Core.AddScript(self, engine_context, new_script_handle);
    if (!try AddScriptTypeTag(new_script_context, engine_context, script_type)) unreachable;
}

/// Gives a script child the tag for script_type, which is what has it run. False, with nothing added, if script_type
/// is not a game context script
pub fn AddScriptTypeTag(script: GameContext, engine_context: *EngineContext, script_type: ScriptAsset.ScriptType) !bool {
    switch (script_type) {
        .GameContextGameStart => _ = try script.AddComponent(engine_context, GameModeComponents.OnGameStartScript{}),
        else => return false,
    }
    return true;
}

pub const AddComponentScript = Core.AddComponentScript;

fn _ValidateScriptType(script_type: ScriptAsset.ScriptType) void {
    std.debug.assert(script_type == .GameContextGameStart);
}

//TODO: move to GCManager
//pub fn CreateGameModeConfig(self: *GameMode, engine_context: *EngineContext, config: NewGameModeConfig) !void {
//    if (config.bAddUUIDComponent) {
//        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
//        const new_random = io_source.interface();
//        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = new_random.int(u64) });
//        try self.mWorldManager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
//    }
//    if (config.bAddNameComponent) {
//        var new_name_component: NameComponent = .empty;
//        _ = try new_name_component.mName.print(engine_context.EngineAllocator(), "New Entity", .{});
//        _ = try self.AddComponent(engine_context, new_name_component);
//    }
//}
