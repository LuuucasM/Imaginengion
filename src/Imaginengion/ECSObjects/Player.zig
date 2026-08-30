const std = @import("std");
pub const Type = u32;
pub const ECSManagerPlayer = @import("../Scene/SceneManager.zig").ECSManagerPlayer;
pub const NullObject: Type = std.math.maxInt(Type);
const EngineContext = @import("../Core/EngineContext.zig");
const Entity = @import("Entity.zig");
const PlayerComponents = @import("../ECSComponents/PComponents.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const PlayerNameComponent = PlayerComponents.NameComponent;
const UUIDComponent = PlayerComponents.UUIDComponent;
const PlayerMic = PlayerComponents.MicComponent;
const TextureFormat = @import("../Assets/Assets.zig").Texture2D.TextureFormat;
const VertexArray = @import("../VertexArrays/VertexArray.zig");
const VertexBuffer = @import("../VertexBuffers/VertexBuffer.zig");
const RenderTargetComponent = PlayerComponents.RenderTargetComponent;
const IndexBuffer = @import("../IndexBuffers/IndexBuffer.zig");
const SceneManager = @import("../Scene/SceneManager.zig");
const EntityComponents = @import("../ECSComponents/EComponents.zig");
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const PlayerParentComponent = @import("../ECS/Components.zig").ParentComponent(Type);
const PlayerChildComponent = @import("../ECS/Components.zig").ChildComponent(Type);
const ChildType = @import("../ECS/ECSManager.zig").ChildType;
const PathType = @import("../Assets//AssetManager.zig").PathType;
const Assets = @import("../Assets/Assets.zig");
const ScriptAsset = Assets.ScriptAsset;
const AssetHandle = @import("AssetHandle.zig");
const ScriptComponent = PlayerComponents.ScriptComponent;
const Player = @This();
const ECSCore = @import("ECSObject.zig").Core;
const WorldManager = @import("../Core/WorldManager.zig");

const Core = ECSCore(Player);

pub const NewPlayerConfig = struct {
    bAddNameComponent: bool = false,
    bAddUUIDComponent: bool = false,
    bAddPossessComponent: bool = false,
    bAddMicComponent: bool = false,
    bAddRenderComponent: bool = false,
};

pub const uninit: Player = .{
    .mID = NullObject,
    .mManager = undefined,
};

mID: Type,
mManager: *WorldManager,

pub const AddComponent = Core.AddComponent;

pub const RemoveCOmponent = Core.RemoveComponent;

pub const GetComponent = Core.GetComponent;

pub const HasComponent = Core.HasComponent;

pub const GetName = Core.GetName;

pub const GetUUID = Core.GetUUID;

pub const Duplicate = Core.Duplicate;

pub const Delete = Core.Delete;

pub fn Possess(self: Player, entity: Entity) void {
    if (entity.GetComponent(PlayerSlotComponent)) |ps_component| {
        self.GetComponent(PossessComponent).?.mPossessedEntity = entity;
        ps_component.mPlayerEntity = self;
    } else {
        std.log.warn("Player {d} could not possess entity {d}", .{ self.mEntityID, entity.mEntityID });
    }
}

//NOTE: no scripts for players yet
//pub fn AddComponentScript(self: Player, engine_context: *EngineContext, new_script_handle: AssetHandle) !void {
//    const script_asset = try new_script_handle.GetAsset(engine_context, ScriptAsset);
//    const script_type = script_asset.GetScriptType();
//    _ValidateScriptType() //add assert to make sure the type is an allowed type
//
//    const new_script_entity = Core.AddScript(self, engine_context, new_script_handle);
//
//    _ = switch (script_asset.GetScriptType()) {
//        else => @panic("This shouldnt happen!"),
//    };
//}

//TODO: Move to PManager
//pub fn CreatePlayerConfig(self: *Player, engine_context: *EngineContext, config: NewPlayerConfig) !void {
//    if (config.bAddUUIDComponent) {
//        const io_source = std.Random.IoSource{ .io = engine_context.Io() };
//        const new_random = io_source.interface();
//        const new_uuid_component = try self.AddComponent(engine_context, UUIDComponent{ .ID = new_random.int(u64) });
//        try self.mScenemanager.AddUUID(engine_context.EngineAllocator(), new_uuid_component.ID, self.mEntityID);
//    }
//    if (config.bAddNameComponent) {
//        var new_name_component: PlayerNameComponent = .empty;
//        _ = try new_name_component.mName.print(engine_context.EngineAllocator(), "New Entity", .{});
//        _ = try self.AddComponent(engine_context, new_name_component);
//    }
//    if (config.bAddPossessComponent) {
//        _ = try self.AddComponent(engine_context, PossessComponent{});
//    }
//    if (config.bAddMicComponent) {
//        _ = try self.AddComponent(engine_context, PlayerMic{});
//    }
//    if (config.bAddRenderComponent) {
//        _ = try self.AddRenderTarget(engine_context);
//    }
//}

pub const IsActive = Core.IsActive;

pub const IsValidID = Core.IsIDValid;

pub const Invalidate = Core.Invalidate;
