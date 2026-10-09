const std = @import("std");
const EngineContext = @import("../../Core/EngineContext.zig");
const UIElement = @import("../../ECSObjects/UIElement.zig");
const UIComponents = @import("../UIComponents.zig");
const JsonUtils = @import("../../Serializer/JsonUtils.zig");
const RefMap = @import("../../ECSObjects/ECSObject.zig").RefMap;
const UIElementComponent = @This();

pub const Editable: bool = true;
pub const Name: []const u8 = "UIElementComponent";

/// Gives the entity a UI element: the UI-only side of it, kept in the UIManager's ECS (see UIElement.zig), which holds
/// what the entity does as UI, such as being typed into or opening as a popup. Edited in the UI Element panel. The
/// element is made for it when the component is added, and every copy of the entity (duplicate, template, a copied
/// world) gets an element of its own. Saved with the element's components inside it
mElement: UIElement = .uninit,

/// The element isn't deleted here: the UIManager lets go of an element at the end of the frame once its entity no
/// longer points at it, the way the audio manager lets go of voices whose source has gone
pub fn Deinit(_: *UIElementComponent, _: *EngineContext) void {}

/// A copy gets an element of its own with the same settings. The UIManager tells it which entity it belongs to once
/// the copy is on one (UIManager.Adopt)
pub fn Clone(self: *const UIElementComponent, engine_context: *EngineContext) !UIElementComponent {
    return .{ .mElement = try engine_context.mUIManager.CopyElement(engine_context, self.mElement) };
}

/// A copy in a template's copy: what its element's components point at in the template is pointed at the copies
pub fn RemapRefs(self: *UIElementComponent, ref_map: *const RefMap) void {
    if (!self.mElement.IsActive()) return;
    inline for (UIComponents.SerializeList) |component_type| {
        if (@hasDecl(component_type, "RemapRefs")) {
            if (self.mElement.GetComponent(component_type)) |component| component.RemapRefs(ref_map);
        }
    }
}

/// The element's components, as an object of component name -> component
pub fn jsonStringify(self: *const UIElementComponent, jw: anytype) !void {
    try jw.beginObject();
    if (self.mElement.IsActive()) {
        inline for (UIComponents.SerializeList) |component_type| {
            if (self.mElement.GetComponent(component_type)) |component| {
                try jw.objectField(component_type.Name);
                try jw.write(component);
            }
        }
    }
    try jw.endObject();
}

/// Makes the element as it reads it, so its components have somewhere to go. Which entity it belongs to is set once
/// the component is on one
pub fn jsonParse(frame_allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) std.json.ParseError(@TypeOf(source.*))!UIElementComponent {
    const engine_context = JsonUtils.EngineContextFromAllocator(frame_allocator);
    const element = engine_context.mUIManager.NewElement(engine_context) catch return error.OutOfMemory;

    if (.object_begin != try source.next()) return error.UnexpectedToken;
    while (true) {
        const key = switch (try source.nextAllocMax(frame_allocator, .alloc_if_needed, options.max_value_len.?)) {
            .object_end => break,
            inline .string, .allocated_string => |slice| slice,
            else => return error.UnexpectedToken,
        };
        inline for (UIComponents.SerializeList) |component_type| {
            if (std.mem.eql(u8, key, component_type.Name)) {
                const component = try std.json.innerParse(component_type, frame_allocator, source, options);
                _ = element.AddComponent(engine_context, component) catch return error.OutOfMemory;
                break;
            }
        } else {
            try source.skipValue();
        }
    }
    return .{ .mElement = element };
}
