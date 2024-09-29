const SystemManager = @This();

pub fn RegisterSystem(self: SystemManager, comptime SystemType: type, comptime ComponentTypes: anytype) void {
    _ = self;
    _ = SystemType;
    _ = ComponentTypes;
    //create the component array for this system's component types
    //register system with system manager
}
pub fn SystemOnUpdate(self: SystemManager, comptime SystemType: type) void {
    _ = self;
    _ = SystemType;
    //call the system
    //process any events that occured
}
