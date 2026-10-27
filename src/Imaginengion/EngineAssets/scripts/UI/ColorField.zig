const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const UIEvent = @import("IM").UIEvent;
const WidgetActions = @import("IM").WidgetActions;
const EntityComponents = @import("IM").EntityComponents;
const ColorField = @This();

/// Stock widget script: a color field, whose swatch shows its color again whenever one of its channels (the number
/// fields inside it) changes (see WidgetActions.UpdateSwatch). Read the color with WidgetActions.ColorOf
/// Hands the change on (.Continue): the entity's own scripts and the ones it is inside still hear it
pub const OnUIEvent = struct {
    /// What it touches, through WidgetActions.UpdateSwatch: reads the channels' values and colors the swatch's surface
    pub const Reads = &.{EntityComponents.AttribComponent};
    pub const Writes = &.{EntityComponents.SurfaceComponent};

    pub fn Run(_: *ColorField, engine_context: *EngineContext, owner: Entity, event: *const UIEvent) ScriptResult {
        _ = engine_context;
        switch (event.*) {
            .ValueChanged => |changed| {
                if (changed.mTarget.mID != owner.mID) WidgetActions.UpdateSwatch(owner);
            },
            else => {},
        }
        return .Continue;
    }
};
