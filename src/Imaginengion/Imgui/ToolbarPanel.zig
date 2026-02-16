const imgui = @import("../Core/CImports.zig").imgui;
const std = @import("std");
const ImguiEvent = @import("../Events/ImguiEvent.zig").ImguiEvent;
const ImguiEventManager = @import("../Events/ImguiEventManager.zig");
const AssetHandle = @import("../Assets/AssetHandle.zig");
const ImguiManager = @import("Imgui.zig");
const Texture2D = @import("../Assets/Assets.zig").Texture2D;
const SceneManager = @import("../Scene/SceneManager.zig");
const GroupQuery = @import("../ECS/ComponentManager.zig").GroupQuery;
const EntityComponents = @import("../GameObjects/Components.zig");
const PlayerSlotComponent = EntityComponents.PlayerSlotComponent;
const Entity = @import("../GameObjects/Entity.zig");
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const SceneComponents = @import("../Scene/SceneComponents.zig");
const SpawnPossComponent = SceneComponents.SpawnPossComponent;
const SceneLayer = @import("../Scene/SceneLayer.zig");
const Player = @import("../Players/Player.zig");
const PlayerComponents = @import("../Players/Components.zig");
const PossessComponent = PlayerComponents.PossessComponent;
const ToolbarPanel = @This();

pub const EditorState = enum(u2) {
    Play = 0,
    Stop = 1,
};

pub const StartKind = union(enum) {
    PossessEntityUUID: u64,
};

pub const StartDescriptor = struct {
    mSceneUUID: u64,
    mStartKind: StartKind,

    pub fn Possess(self: StartDescriptor, player: Player, scene_manager: *SceneManager) !void {
        switch (self.mStartKind) {
            .PossessEntity => |entity_uuid| {
                if (scene_manager.GetEntityByUUID(entity_uuid)) |entity| {
                    entity.Possess(player);
                    player.Possess(entity);
                } else {
                    const possess_component = player.GetComponent(PossessComponent);
                    possess_component.mPossessedEntity = Entity.EntityRef{ .UUID = .{ .mID = entity_uuid, .mSceneManager = scene_manager } };
                }
            },
        }
    }
};

mP_Open: bool = true,
mState: EditorState = .Stop,
mPlayIcon: AssetHandle = undefined,
mStopIcon: AssetHandle = undefined,
mStartDescriptor: ?StartDescriptor = null,

pub fn Init(self: *ToolbarPanel, engine_context: *EngineContext) !void {
    self.mPlayIcon = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/play.png", .Eng);
    self.mStopIcon = try engine_context.mAssetManager.GetAssetHandleRef(engine_context.EngineAllocator(), "assets/textures/stop.png", .Eng);
}

pub fn Deinit(self: *ToolbarPanel) void {
    self.mPlayIcon.ReleaseAsset();
    self.mStopIcon.ReleaseAsset();
}

pub fn OnImguiRender(self: *ToolbarPanel, world_type: EngineContext.WorldType, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("ToolbarPanel OIR", @src());
    defer zone.Deinit();

    const scene_manager = switch (world_type) {
        .Game => engine_context.mGameWorld,
        .Editor => engine_context.mEditorWorld,
        .Simulate => engine_context.mSimulateWorld,
    };

    if (self.mP_Open == false) return;
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_WindowPadding, .{ .x = 0.0, .y = 2.0 });
    imgui.igPushStyleVar_Vec2(imgui.ImGuiStyleVar_ItemInnerSpacing, .{ .x = 0.0, .y = 0.0 });
    defer imgui.igPopStyleVar(2);

    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_Button, .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 });
    const colors = imgui.igGetStyle().*.Colors;
    const buttonHovered = colors[imgui.ImGuiCol_ButtonHovered];
    const buttonActive = colors[imgui.ImGuiCol_ButtonActive];
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonHovered, .{ .x = buttonHovered.x, .y = buttonHovered.y, .z = buttonHovered.z, .w = 0.5 });
    imgui.igPushStyleColor_Vec4(imgui.ImGuiCol_ButtonActive, .{ .x = buttonActive.x, .y = buttonActive.y, .z = buttonActive.z, .w = 0.5 });
    defer imgui.igPopStyleColor(3);

    const config = imgui.ImGuiWindowFlags_NoDecoration | imgui.ImGuiWindowFlags_NoScrollbar | imgui.ImGuiWindowFlags_NoScrollWithMouse;
    _ = imgui.igBegin("##Toolbar", null, config);
    defer imgui.igEnd();

    const size = imgui.igGetWindowHeight();
    const texture: *Texture2D = if (self.mState == .Play) try self.mStopIcon.GetAsset(engine_context, Texture2D) else try self.mPlayIcon.GetAsset(engine_context, Texture2D);

    var window_size: imgui.struct_ImVec2 = undefined;
    imgui.igGetContentRegionAvail(&window_size);

    // Center the group: calculate total width of button + combo + spacing
    const button_width = size;
    const combo_width: f32 = 120.0; // Estimate or measure your combo width
    const spacing: f32 = 8.0; // Default ImGui spacing
    const total_width = button_width + spacing + combo_width;
    const start_x = (window_size.x * 0.5) - (total_width * 0.5);

    imgui.igSetCursorPosX(start_x);

    // Button
    const texture_id = @as(*anyopaque, @ptrFromInt(@as(usize, texture.GetID())));
    if (imgui.igImageButtonEx(
        texture.GetID(),
        texture_id,
        .{ .x = size, .y = size },
        .{ .x = 0, .y = 0 },
        .{ .x = 1, .y = 1 },
        .{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 },
        imgui.ImGuiButtonFlags_None,
    ) == true) {
        if (self.mStartDescriptor != null and self.mState == .Stop) {
            try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), ImguiEvent{
                .ET_ChangeEditorStateEvent = .{ .mEditorState = .Play },
            });
            self.mState = .Play;
        } else if (self.mState == .Play) {
            try engine_context.mImguiEventManager.Insert(engine_context.EngineAllocator(), ImguiEvent{
                .ET_ChangeEditorStateEvent = .{ .mEditorState = .Stop },
            });
            self.mState = .Stop;
        }
    }

    // Place combo box on the same line, with spacing
    imgui.igSameLine(0.0, spacing);

    // Combo box
    imgui.igPushItemWidth(combo_width); // combo_width should be wide enough, e.g., 120.0 or more

    var combo_text: []const u8 = "None\x00";
    if (self.mStartDescriptor) |start_descriptor| {
        // Ensure null-terminated string for ImGui
        if (std.meta.activeTag(start_descriptor.mStartKind) == .PossessEntity) {
            const entity = start_descriptor.mStartKind.PossessEntity;
            combo_text = try std.fmt.allocPrint(engine_context.FrameAllocator(), "PossessEntity - {s}\x00", .{entity.GetName()});
        }
    }
    if (imgui.igBeginCombo("##PlayLocation", @ptrCast(combo_text.ptr), imgui.ImGuiComboFlags_None)) {
        defer imgui.igEndCombo();

        if (imgui.igSelectable_Bool("None\x00", self.mStartEntity == null, 0, .{ .x = 0, .y = 0 })) {
            self.mStartDescriptor = null;
        }

        const spaw_poss = try scene_manager.GetSceneGroup(engine_context.FrameAllocator(), .{ .Component = SpawnPossComponent });

        for (spaw_poss.items) |scene_id| {
            const scene_layer = scene_manager.GetSceneLayer(scene_id);
            const spawn_poss = scene_layer.GetComponent(SpawnPossComponent).?;
            if (spawn_poss.mEntity) |spawn_entity_id| {
                const entity = scene_manager.GetEntity(spawn_entity_id);
                const name_cstr = try std.fmt.allocPrint(engine_context.FrameAllocator(), "{s}\x00", .{entity.GetName()});
                if (imgui.igSelectable_Bool(name_cstr, false, 0, .{ .x = 0, .y = 0 })) {
                    self.mStartDescriptor = StartDescriptor{
                        .mScene = scene_layer,
                        .mStartKind = .{ .PossessEntity = entity },
                    };
                }
            }
        }
    }
    imgui.igPopItemWidth();
}

pub fn OnTogglePanelEvent(self: *ToolbarPanel) void {
    self.mP_Open = !self.mP_Open;
}
