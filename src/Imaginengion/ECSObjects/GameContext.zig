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
const PathType = @import("../Assets/AssetManager.zig").PathType;
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const GameContext = @This();
const ECSCore = @import("ECSObject.zig").Core;
const AssetHandle = @import("AssetHandle.zig");

const Core = ECSCore(GameContext);

pub const NewGameModeConfig = struct {
    bAddUUIDComponent: bool = false,
    bAddNameComponent: bool = false,
};

pub const uninit: GameContext = .{
    .mID = NullObject,
    .MManager = undefined,
};

mID: Type,
mManager: *WorldManager,

pub const AddComponent = Core.AddComponent;

pub const RemoveComponent = Core.RemoveComponent;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetName = Core.GetName;

pub const Duplicate = Core.Duplicate;

pub const GetUUID = Core.GetUUID;

pub const Delete = Core.Delete;

pub const IsActive = Core.IsActive;

pub const IsValidID = Core.IsIDValid;

pub const Invalidate = Core.Invalidate;

pub fn CreateChild(self: GameContext, engine_context: *EngineContext, child_type: ChildType, new_gamemode_config: NewGameModeConfig) !GameContext {
    var child_gamemode = Core.CreateChild(self, engine_context, child_type);
    @compileLog("TODO: change to move NewGmaeModeConfig into the GCManager instead of in GameContext");
    try child_gamemode.CreateGameModeConfig(engine_context, new_gamemode_config);
    return child_gamemode;
}

//NOTE: no scripts yet for GameContext
//pub fn AddScript(self: GameContext, engine_context: *EngineContext, new_script_handle: AssetHandle) !void {
//    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);
//    const script_type = script_asset.GetScriptType();
//    _ValidateScriptType() //add assert to make sure the type is an allowed type
//
//    const new_script_entity = try Core.AddScript(self, engine_context, new_script_handle);
//
//    // Add the appropriate script type component based on the script asset
//    switch (script_asset.GetScriptType()) {
//        else => @panic("this shouldnt happen!\n"),
//    }
//}

//TODO: move to GCManager
//pub fn CreateGameModeConfig(self: *GameMode, engine_context: *EngineContext, config: NewGameModeConfig) !void {
//    if (config.bAddUUIDComponent) {
//        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
//        const new_random = io_source.interface();
//        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = new_random.int(u64) });
//        try self.mScenemanager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
//    }
//    if (config.bAddNameComponent) {
//        var new_name_component: NameComponent = .empty;
//        _ = try new_name_component.mName.print(engine_context.EngineAllocator(), "New Entity", .{});
//        _ = try self.AddComponent(engine_context, new_name_component);
//    }
//}
