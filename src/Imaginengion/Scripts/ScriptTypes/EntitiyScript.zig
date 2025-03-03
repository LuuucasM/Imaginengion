const std = @import("std");
const Entity = @import("IM").Entity;
const ComponentsList = @import("../ScriptTypes.zig").ComponentsList;
const EntityScript = @This();

mEntity: Entity,
mScript: std.DynLib,

//pub export fn PreInputUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PostInputUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PrePhysicsUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PostPhysicsUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PreGameLogicUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PostGameLogicUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PreRenderUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PostRenderUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PreAudioUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PostAudioUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PreNetworkingUpdate(entity: Entity) void {
//    //your code goes here
//}
//
//pub export fn PostNetworkingUpdate(entity: Entity) void {
//    //your code goes here
//}

pub const Ind: usize = blk: {
    for (ComponentsList, 0..) |component_type, i| {
        if (component_type == EntityScript) {
            break :blk i;
        }
    }
};
