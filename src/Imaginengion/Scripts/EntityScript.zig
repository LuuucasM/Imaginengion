const Entity = @import("IM").Entity;
const ScriptFuncDef = @import("IM").ScriptFuncDef;

const ScriptMask: u16 = ScriptFuncDef.None;

pub export fn GetScriptMask() u16 {
    return ScriptMask;
}

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
