const ListInd = @import("../ECS/Components.zig").ListInd;
pub const ElementOwnerComponent = @import("UIElement/ElementOwnerComponent.zig");
pub const TextInputComponent = @import("UIElement/TextInputComponent.zig");
pub const PopupComponent = @import("UIElement/PopupComponent.zig");
pub const ScrollComponent = @import("UIElement/ScrollComponent.zig");
pub const ScrollStateComponent = @import("UIElement/ScrollStateComponent.zig");
pub const StyleComponent = @import("UIElement/StyleComponent.zig");
pub const PopupRefComponent = @import("UIElement/PopupRefComponent.zig");
pub const NumberFieldComponent = @import("UIElement/NumberFieldComponent.zig");
pub const SelectionGroupComponent = @import("UIElement/SelectionGroupComponent.zig");

/// The components of the UIManager's objects, its UI elements: the parts of an entity's UI that only the UI ever uses
/// (see UIElement.zig)
pub const ComponentsList = [_]type{
    ElementOwnerComponent,
    TextInputComponent,
    PopupComponent,
    ScrollComponent,
    ScrollStateComponent,
    StyleComponent,
    PopupRefComponent,
    NumberFieldComponent,
    SelectionGroupComponent,
};

/// What an element is saved with, inside its entity's UIElementComponent, and copied with when the entity is.
/// ElementOwnerComponent and ScrollStateComponent are left out: which entity owns it is set again whenever one takes
/// it, and how far it is scrolled is how it is being used right now
pub const SerializeList = [_]type{
    TextInputComponent,
    PopupComponent,
    ScrollComponent,
    StyleComponent,
    PopupRefComponent,
    NumberFieldComponent,
    SelectionGroupComponent,
};

/// What the UI Element panel lists and offers to add
pub const ComponentsPanelList = [_]type{
    TextInputComponent,
    PopupComponent,
    ScrollComponent,
    StyleComponent,
    PopupRefComponent,
    NumberFieldComponent,
    SelectionGroupComponent,
};

pub const EComponents = enum(u16) {
    ElementOwnerComponent = ListInd(&ComponentsList, ElementOwnerComponent),
    TextInputComponent = ListInd(&ComponentsList, TextInputComponent),
    PopupComponent = ListInd(&ComponentsList, PopupComponent),
    ScrollComponent = ListInd(&ComponentsList, ScrollComponent),
    ScrollStateComponent = ListInd(&ComponentsList, ScrollStateComponent),
    StyleComponent = ListInd(&ComponentsList, StyleComponent),
    PopupRefComponent = ListInd(&ComponentsList, PopupRefComponent),
    NumberFieldComponent = ListInd(&ComponentsList, NumberFieldComponent),
    SelectionGroupComponent = ListInd(&ComponentsList, SelectionGroupComponent),
};
