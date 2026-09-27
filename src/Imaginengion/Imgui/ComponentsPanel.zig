const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Entity = @import("../ECSObjects/Entity.zig");
const SceneLayer = @import("../ECSObjects/Scene.zig");
const Player = @import("../ECSObjects/Player.zig");
const GameMode = @import("../ECSObjects/GameContext.zig");

const Renderer = @import("../Renderer/Renderer.zig");

const ComponentsPanel = @This();

const EngineContext = @import("../Core/EngineContext.zig");

const Assets = @import("../ECSComponents/AComponents.zig");
const TransformComponent = @import("../ECSComponents/Shared/TransformComponent.zig");
const RigidBodyComponent = @import("../ECSComponents/Entity/RigidBodyComponent.zig");
const PossessComponent = @import("../ECSComponents/Player/PossessComponent.zig");
const OverlayComponent = @import("../ECSComponents/Player/OverlayComponent.zig");
const AudioComponent = @import("../ECSComponents/Entity/AudioComponent.zig");
const SceneComponent = @import("../ECSComponents/Scene/SceneComponent.zig");
const LayoutComponent = @import("../ECSComponents/Entity/LayoutComponent.zig");
const LayoutItemComponent = @import("../ECSComponents/Entity/LayoutItemComponent.zig");
const TextComponent = @import("../ECSComponents/Entity/TextComponent.zig");
const LayoutSystem = @import("../UI/LayoutSystem.zig");
const ImguiManager = @import("Imgui.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;

const Tracy = @import("../Core/Tracy.zig");

_P_Open: bool = true,

pub fn Init(_: *ComponentsPanel) void {}

pub fn OnImguiRender(self: ComponentsPanel, engine_context: *EngineContext, selected_object_opt: *?SelectedObject) !void {
    const zone = Tracy.ZoneInit("ComponentsPanel::OnImguiRender", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;

    if (selected_object_opt.*) |selected_object| {
        switch (selected_object) {
            .entity => |e| try RenderBegin(Entity, engine_context, e),
            .scene_layer => |s| try RenderBegin(SceneLayer, engine_context, s),
            .player => |p| try RenderBegin(Player, engine_context, p),
            .gamecontext => |g| try RenderBegin(GameMode, engine_context, g),
        }
        defer imgui.igEnd();

        switch (selected_object) {
            .entity => |e| try RenderComponents(Entity, engine_context, e),
            .scene_layer => |s| try RenderComponents(SceneLayer, engine_context, s),
            .player => |p| try RenderComponents(Player, engine_context, p),
            .gamecontext => |g| try RenderComponents(GameMode, engine_context, g),
        }
    } else {
        _ = imgui.igBegin("Components - No Entity###Components\x00", null, 0);
        defer imgui.igEnd();
    }
}

fn RenderBegin(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const object_name = object.GetName();
    const name_len = std.mem.indexOf(u8, object_name, &.{0}) orelse object_name.len;
    const trimmed_name = object_name[0..name_len];
    const name = try std.fmt.allocPrintSentinel(engine_context.FrameAllocator(), "Components - {s}###Components", .{trimmed_name}, 0);

    _ = imgui.igBegin(name.ptr, null, 0);
}

/// The component list of one object, drawn into the current window (a template window draws its own)
pub fn RenderComponents(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    try ObjectImguiRender(ObjectType, engine_context, object);

    //the panel's own context menu, submitted after the components so imgui knows which item
    //(if any) the cursor is over. NoOpenOverItems means this only opens on a right click that
    //landed on empty space; a click on a component is claimed by that component's
    //BeginPopupContextItem instead, so only one popup ever opens.
    if (imgui.igBeginPopupContextWindow("RightClickPopup", imgui.ImGuiPopupFlags_MouseButtonRight | imgui.ImGuiPopupFlags_NoOpenOverItems)) {
        defer imgui.igEndPopup();
        try NewObjectComponentPopup(ObjectType, engine_context, object);
    }
}

pub fn OnTogglePanelEvent(self: *ComponentsPanel) void {
    self._P_Open = !self._P_Open;
}

fn ObjectImguiRender(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const traits = ObjectTraits(ObjectType);
    inline for (traits.ComponentsPanelList) |component_type| {
        if (object.HasComponent(component_type)) {
            try PrintObjectComponent(component_type, engine_context, object);
        }
    }
}

fn PrintObjectComponent(comptime component_type: type, engine_context: *EngineContext, object: anytype) !void {
    const tree_flags = imgui.ImGuiTreeNodeFlags_OpenOnArrow;
    const is_tree_open = imgui.igTreeNodeEx_Str(@typeName(component_type), tree_flags);
    //a component the object can't work without declares `Removable = false` and gets no delete option
    const is_removable = comptime !@hasDecl(component_type, "Removable") or component_type.Removable;
    if (is_removable and imgui.igBeginPopupContextItem(@typeName(component_type), imgui.ImGuiPopupFlags_MouseButtonRight)) {
        defer imgui.igEndPopup();

        if (imgui.igMenuItem_Bool("Delete Component", "", false, true)) {
            try object.RemoveComponent(engine_context, component_type);
        }
    }
    if (is_tree_open) {
        defer imgui.igTreePop();
        if (@hasDecl(component_type, "EditorRender")) {
            const component_ptr = object.GetComponent(component_type).?;
            try component_ptr.EditorRender(engine_context);

            //the transform widgets write straight into the component, so this is the one write
            //path that cannot go through Entity's setters. Tag it while the panel is open rather
            //than trying to detect a change: it is a single entity, and a missed edit would leave
            //a stale world transform.
            if (comptime component_type == TransformComponent and @TypeOf(object) == Entity) {
                try object.MarkTransformDirty(engine_context);
                //x and y of something layout places snap back as they're dragged, z stays editable
                if (LayoutSystem.IsPlacedByLayout(object)) try object.MarkLayoutDirty(engine_context);
            }

            //a layout setting, or the text a leaf fits to, changes how the whole tree it is in is laid out. Tagged while the panel is open
            //for the same reason as the transform: one entity, and a missed edit would leave the layout stale
            if (comptime (component_type == LayoutComponent or component_type == LayoutItemComponent or component_type == TextComponent) and @TypeOf(object) == Entity) {
                try object.MarkLayoutDirty(engine_context);
            }

            //same story for the mass input: it recomputes _InvMass in place, so the tags that were
            //derived from it have to be brought back in step
            if (comptime component_type == RigidBodyComponent and @TypeOf(object) == Entity) {
                try object.SyncBodyTags(engine_context);
            }
        }

        //the layer is the scene's layer tag, which the panel doesn't list: shown here, not edited,
        //since the scene stack slots a scene by its layer when it is created
        if (comptime component_type == SceneComponent and @TypeOf(object) == SceneLayer) {
            imgui.igText("Layer: %s", @tagName(object.GetLayer()).ptr);
        }

        //possessing links both the player and the entity's PlayerSlotComponent, so the component
        //cannot render itself: only here do we have the Player to call Possess on
        if (comptime component_type == PossessComponent and @TypeOf(object) == Player) {
            const possess_component = object.GetComponent(PossessComponent).?;
            if (try ImguiManager.RenderEntityRef(engine_context, &possess_component.mPossessedEntity, "Possessed Entity")) |new_entity| {
                if (new_entity.IsActive()) {
                    object.Possess(new_entity);
                } else {
                    possess_component.mPossessedEntity = .uninit;
                }
            }
        }

        //like PossessComponent, rendered here rather than by the component: only here do we have the
        //player, to check that a dropped scene is an overlay in its world
        if (comptime component_type == OverlayComponent and @TypeOf(object) == Player) {
            const overlay_component = object.GetComponent(OverlayComponent).?;
            if (try ImguiManager.RenderSceneRef(engine_context, &overlay_component.mScene, "Overlay Scene")) |new_scene| {
                if (!new_scene.IsActive()) {
                    overlay_component.mScene = .uninit;
                } else if (new_scene.mManager != object.mManager) {
                    std.log.warn("An overlay has to be a scene in the same world as the player", .{});
                } else if (new_scene.GetLayer() != .OverlayLayer) {
                    std.log.warn("Only an overlay scene can be shown as an overlay, not a game layer scene", .{});
                } else {
                    overlay_component.mScene = new_scene;
                }
            }
        }

        //playing needs the entity the component is on, which EditorRender does not get
        if (comptime component_type == AudioComponent and @TypeOf(object) == Entity) {
            if (imgui.igButton("Preview", .{ .x = 0.0, .y = 0.0 })) {
                _ = try object.PlayAudio(engine_context);
            }
            imgui.igSameLine(0.0, -1.0);
            if (imgui.igButton("Stop", .{ .x = 0.0, .y = 0.0 })) {
                object.StopAudio();
            }
        }
    }
}

fn NewObjectComponentPopup(comptime ObjectType: type, engine_context: *EngineContext, object: ObjectType) !void {
    const traits = ObjectTraits(ObjectType);
    inline for (traits.ComponentsPanelList) |component_type| {
        //a component that only makes sense set up by the engine declares `Addable = false` and is shown but not offered here
        const is_addable = comptime !@hasDecl(component_type, "Addable") or component_type.Addable;
        if (is_addable and !object.HasComponent(component_type)) {
            if (imgui.igMenuItem_Bool(component_type.Name.ptr, "", false, true)) {
                defer imgui.igCloseCurrentPopup();
                _ = try object.AddComponent(engine_context, component_type{});
            }
        }
    }
}

fn ObjectTraits(comptime T: type) type {
    if (T == Entity) {
        const EntityComponents = @import("../ECSComponents/EComponents.zig");
        return struct {
            const ComponentsPanelList = EntityComponents.ComponentPanelList;
        };
    } else if (T == SceneLayer) {
        const SceneComponents = @import("../ECSComponents/SComponents.zig");
        return struct {
            const ComponentsPanelList = SceneComponents.ComponentsPanelList;
        };
    } else if (T == Player) {
        const PlayerComponents = @import("../ECSComponents/PComponents.zig");
        return struct {
            const ComponentsPanelList = PlayerComponents.ComponentsPanelList;
        };
    } else if (T == GameMode) {
        const GameModeComponents = @import("../ECSComponents/GCComponents.zig");
        return struct {
            const ComponentsPanelList = GameModeComponents.ComponentsPanelList;
        };
    } else {
        @compileError(@typeName(T) ++ "This type is not supported currently");
    }
}
