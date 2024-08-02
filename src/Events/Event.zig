const EventNames = @import("EventEnums.zig").EventNames;
const Event = @This();

_VTable: *const VTable,
_Event: *anyopaque,

const VTable = struct {
    GetEventName: *const fn (event: *anyopaque) EventNames,
};

pub fn GetEventName(self: Event) EventNames {
    return self._VTable.GetEventName(self._Event);
}
