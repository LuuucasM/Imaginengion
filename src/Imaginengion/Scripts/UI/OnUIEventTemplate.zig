const std = @import("std");
const EngineContext = @import("IM").EngineContext;
const Entity = @import("IM").Entity;
const ScriptResult = @import("IM").ScriptResult;
const UIEvent = @import("IM").UIEvent;

//The script's variables go here, above its functions. Each one is shown under the script in the Scripts panel, where it
//can be set (an entity dragged onto an Entity), and saved with the object, and every object the script is on has its
//own. Each needs a default, and can be a f32, i32, u32, bool, enum, Vec2/Vec3/Vec4(f32), Entity, SceneLayer, Player
//or GameContext. They are self's fields in the functions below, e.g. self.mSpeed
//mSpeed: f32 = 5.0,

//The functions the engine runs (its hooks) are named for when they run. A script can have any of the ones its object
//takes, e.g. OnUpdate and OnCollisionBegin together, and they all share the variables

/// Function that gets executed for every UI event sent to this entity. Like pointer events, they go to the entity it
/// happened to and then to each one it is inside, so this hears about its children too. Only this entity's own events
/// come here, so there is no need to check who an event is for: switch on what happened. Each event has:
///     mTarget: the entity it actually happened to
/// and then, by event:
///     .FocusGained / .FocusLost: a text input (TextInputComponent on its UI element) got the keyboard, or lost it
///     .TextChanged: its text was typed into, deleted from, pasted into, or put back by Escape
///     .TextSubmitted: the edit was kept, by Enter or a press somewhere else. Read the text off mTarget's TextComponent
///     .PopupOpened / .PopupClosed: a popup opened or closed. mOpener is what it was opened against, if anything
///     .ValueChanged: a widget's value changed, e.g. a checkbox checked (SelectedTag on mTarget) or a row selected
/// return .Continue and the entities this one is inside get the event too, and this entity's other UI scripts
/// return .Handled and it stops here
pub fn OnUIEvent(self: *@This(), engine_context: *EngineContext, owner: Entity, event: *const UIEvent) !ScriptResult {
    _ = self;
    _ = engine_context;
    _ = owner;

    switch (event.*) {
        .TextSubmitted => |submitted| {
            _ = submitted;
            //what entering the text does goes here
        },
        else => {},
    }
    return .Continue;
}
