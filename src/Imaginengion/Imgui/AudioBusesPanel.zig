const std = @import("std");
const imgui = @import("../Core/CImports.zig").imgui;
const Tracy = @import("../Core/Tracy.zig");
const EngineContext = @import("../Core/EngineContext.zig");
const ImguiManager = @import("Imgui.zig");
const Bus = @import("../ECSObjects/Bus.zig");
const VComponents = @import("../ECSComponents/VComponents.zig");
const BusComponent = VComponents.BusComponent;
const VolumeComponent = VComponents.VolumeComponent;
const NameComponent = VComponents.NameComponent;
const AudioBusesPanel = @This();

/// Adding a bus grows the ECS storage the tree's widgets are writing into, so the buttons only record what was asked
/// for and it is done once the whole tree has been drawn. Deleting is queued for the end of the frame anyway
const Action = union(enum) {
    None,
    AddChild: Bus,
    Delete: Bus,
};

_P_Open: bool = false,

/// The bus tree from Master down, with each bus's name, volume and pause, and buttons to add or delete buses
pub fn OnImguiRender(self: *AudioBusesPanel, engine_context: *EngineContext) !void {
    const zone = Tracy.ZoneInit("AudioBusesPanel::OnImguiRender", @src());
    defer zone.Deinit();

    if (self._P_Open == false) return;
    _ = imgui.igBegin("Audio Buses", null, 0);
    defer imgui.igEnd();

    const master_bus = engine_context.mAudioManager.GetMasterBus();
    var action: Action = .None;
    try RenderBus(engine_context, master_bus, master_bus, &action);

    switch (action) {
        .None => {},
        .AddChild => |parent| _ = try parent.CreateChild(engine_context, .Entity, Bus.DefaultConfig),
        .Delete => |bus| try bus.Delete(engine_context),
    }
}

fn RenderBus(engine_context: *EngineContext, bus: Bus, master_bus: Bus, action: *Action) !void {
    const frame_allocator = engine_context.FrameAllocator();

    imgui.igPushID_Int(@intCast(bus.mID));
    defer imgui.igPopID();

    //a bus read from a hand edited file may be missing any of these
    const name_component = bus.GetComponent(NameComponent);
    const name = if (name_component) |component| component.mName.items else "Bus";
    const tree_label = try std.fmt.allocPrintSentinel(frame_allocator, "{s}", .{name}, 0);
    //a fixed id rather than the name, so renaming the bus does not close its node
    if (!imgui.igTreeNodeEx_StrStr("Bus", imgui.ImGuiTreeNodeFlags_DefaultOpen, "%s", tree_label.ptr)) return;
    defer imgui.igTreePop();

    const is_master = bus.mID == master_bus.mID;

    if (!is_master) {
        if (name_component) |component| try ImguiManager.RenderTextInput(engine_context, &component.mName, "Name");
    }
    if (bus.GetComponent(VolumeComponent)) |volume_component| {
        _ = try ImguiManager.RenderFloatDrag(&volume_component.mVolume, "Volume", 0.01, 0.0, 1.0);
    }
    try ImguiManager.RenderBool(&bus.GetComponent(BusComponent).?.mPaused, "Paused");

    if (imgui.igSmallButton("Add Child")) action.* = .{ .AddChild = bus };
    if (!is_master) {
        imgui.igSameLine(0.0, -1.0);
        if (imgui.igSmallButton("Delete")) action.* = .{ .Delete = bus };
    }

    var child_iter = bus.GetIterator(.Child);
    while (child_iter.next()) |child_bus| {
        try RenderBus(engine_context, child_bus, master_bus, action);
    }
}
