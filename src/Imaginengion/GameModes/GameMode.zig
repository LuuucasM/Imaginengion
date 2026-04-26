const std = @import("std");
pub const Type = u32;
pub const NullGameMode: Type = std.math.maxInt(Type);

const EngineContext = @import("../Core/EngineContext.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const GameModeParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const GameModeChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const GameModeComponents = @import("Components.zig");
const UUIDComponent = GameModeComponents.UUIDComponent;
const NameComponent = GameModeComponents.NameComponent;
const ScriptComponent = GameModeComponents.ScriptComponent;
const GenUUID = @import("../Serializer/Serializer.zig").GenUUID;
const PathType = @import("../Assets/Assets.zig").FileMetaData.PathType;
const ScriptAsset = @import("../Assets/Assets.zig").ScriptAsset;
const GameMode = @This();

pub const Iterator = struct {
    pub const IterType = enum {
        Child,
        Script,
    };
    _CurrentGameMode: GameMode,
    _FirstID: Type,
    _IsFirst: bool = true,

    pub fn next(self: *Iterator) ?GameMode {
        if (self._IsFirst) {
            @branchHint(.cold);
            self._IsFirst = false;
        } else {
            if (self._CurrentGameMode.mEntityID == self._FirstID) return null;
        }

        const game_mode = self._CurrentGameMode;

        const gamemode_child_component = game_mode.GetComponent(GameModeChildComponent).?;

        self._CurrentGameMode = GameMode{ .mEntityID = gamemode_child_component.mNext, .mScenemanager = game_mode.mScenemanager };

        return game_mode;
    }
};

pub const NewGameModeConfig = struct {
    bAddUUIDComponent: bool = true,
    bAddNameComponent: bool = true,
};

mEntityID: Type = NullGameMode,
mScenemanager: *SceneManager = undefined,

pub fn AddComponent(self: GameMode, engine_context: *EngineContext, new_component: anytype) !*@TypeOf(new_component) {
    return try self.mScenemanager.mECSManagerGM.AddComponent(engine_context.EngineAllocator(), self.mEntityID, new_component);
}
pub fn RemoveComponent(self: GameMode, engine_allocator: std.mem.Allocator, comptime component_type: type) !void {
    try self.mScenemanager.mECSManagerGM.RemoveComponent(engine_allocator, component_type, self.mEntityID);
}
pub fn GetComponent(self: GameMode, comptime component_type: type) ?*component_type {
    return self.mScenemanager.mECSManagerGM.GetComponent(component_type, self.mEntityID);
}
pub fn HasComponent(self: GameMode, comptime component_type: type) bool {
    return self.mScenemanager.mECSManagerGM.HasComponent(component_type, self.mEntityID);
}

pub fn GetName(self: GameMode) []const u8 {
    return self.mScenemanager.mECSManagerGM.GetComponent(NameComponent, self.mEntityID).?.*.mName.items;
}

pub fn Duplicate(self: GameMode) !GameMode {
    return try self.mScenemanager.mECSManagerGM.DuplicateEntity(self.mEntityID);
}
pub fn Delete(self: GameMode, engine_context: *EngineContext) !void {
    try self.mScenemanager.mECSManagerGM.DestroyEntity(engine_context.EngineAllocator(), self.mEntityID);
}

pub fn IsActive(self: GameMode) bool {
    return self.IsValidID() and self.mScenemanager.mECSManagerGM.IsActiveEntity(self.mEntityID);
}

pub fn IsValidID(self: GameMode) bool {
    return self.mEntityID != NullGameMode;
}

pub fn CreateChild(self: GameMode, engine_context: *EngineContext, child_type: ChildType, new_gamemode_config: NewGameModeConfig) !GameMode {
    var child_gamemode = GameMode{ .mEntityID = try self.mScenemanager.mECSManagerSC.AddChild(engine_context.EngineAllocator(), self.mEntityID, child_type), .mScenemanager = self.mScenemanager };
    try child_gamemode.CreateGameModeConfig(engine_context, new_gamemode_config);
    return child_gamemode;
}

pub fn AddComponentScript(self: GameMode, engine_context: *EngineContext, rel_path_script: []const u8, path_type: PathType) !void {
    var new_script_handle = try engine_context.mAssetManager.GetAssetHandleRef(engine_context, .{ .File = .{ .rel_path = rel_path_script, .path_type = path_type } });
    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);

    std.debug.assert(script_asset.mScriptType == .EntityInputPressed or script_asset.mScriptType == .EntityOnUpdate);

    // Create the script component with the asset handle
    const new_script_component = ScriptComponent{
        .mScriptAssetHandle = new_script_handle,
    };

    const new_script_entity = try self.CreateChild(engine_context, .Script, .{ .bAddNameComponent = false, .bAddUUIDComponent = false });

    _ = try new_script_entity.AddComponent(engine_context, new_script_component);

    // Add the appropriate script type component based on the script asset
    switch (script_asset.mScriptType) {
        else => @panic("this shouldnt happen!\n"),
    }
}

pub fn CreateGameModeConfig(self: *GameMode, engine_context: *EngineContext, config: NewGameModeConfig) !void {
    if (config.bAddUUIDComponent) {
        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = GenUUID() });
        try self.mScenemanager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
    }
    if (config.bAddNameComponent) {
        var new_name_component = NameComponent{ .mAllocator = engine_context.EngineAllocator() };
        _ = try new_name_component.mName.print(new_name_component.mAllocator, "New Entity", .{});
        _ = try self.AddComponent(engine_context, new_name_component);
    }
}

pub fn GetIterator(self: GameMode, comptime iter_type: Iterator.IterType) ?Iterator {
    if (self.GetComponent(GameModeParentComponent)) |parent_component| {
        const first = switch (iter_type) {
            .Child => parent_component.mFirstEntity,
            .Script => parent_component.mFirstScript,
        };
        if (first == NullGameMode) return null;
        return Iterator{
            ._CurrentGameMode = GameMode{ .mEntityID = first, .mScenemanager = self.mScenemanager },
            ._FirstID = first,
        };
    } else {
        return null;
    }
}
