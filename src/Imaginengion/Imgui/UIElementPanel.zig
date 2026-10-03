const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const UIElement = @import("../ECSObjects/UIElement.zig");
const UIManager = @import("../UI/UIManager.zig");
const UIComponents = @import("../ECSComponents/UIComponents.zig");
const ComponentsPanel = @import("ComponentsPanel.zig");
const SelectedObject = @import("../Programs/EditorProgram.zig").SelectedObject;
const UIElementPanel = @This();

/// The selected entity's UI element: its UI-only components, listed and edited like the Components panel lists the
/// entity's own, with a right click to add or delete them. Opened from the Windows menu or an entity's
/// UIElementComponent, and closed again when it isn't needed: it isn't one of the panels that is always up
_P_Open: bool = false,

pub fn OnImguiRender(self: *UIElementPanel, engine_context: *EngineContext, selected_object_opt: *?SelectedObject) !void {
    const zone = Tracy.ZoneInit("UIElementPanel::OnImguiRender", @src());
    defer zone.Deinit();

    if (!self._P_Open) return;
    _ = imgui.igBegin("UI Element", &self._P_Open, 0);
    defer imgui.igEnd();

    const selected = selected_object_opt.* orelse {
        imgui.igTextUnformatted("Select an entity to see its UI element", null);
        return;
    };
    const entity = switch (selected) {
        .entity => |entity| entity,
        else => {
            imgui.igTextUnformatted("Only an entity can have a UI element", null);
            return;
        },
    };
    if (!entity.IsActive()) return;

    const element = UIManager.ElementOf(entity) orelse {
        imgui.igTextUnformatted("This entity has no UI element. Add a UIElementComponent to it in the Components panel", null);
        return;
    };

    var count: usize = 0;
    inline for (UIComponents.ComponentsPanelList) |component_type| {
        if (element.HasComponent(component_type)) count += 1;
    }
    if (count == 0) imgui.igTextUnformatted("No UI components yet. Right click to add one", null);

    try ComponentsPanel.RenderComponents(UIElement, engine_context, element);

    //a scroll setting changes how the entity's tree is laid out. Tagged while the panel is open, as the Components
    //panel does for the entity's own layout settings
    if (element.HasComponent(UIComponents.ScrollComponent)) try entity.MarkLayoutDirty(engine_context);
}
