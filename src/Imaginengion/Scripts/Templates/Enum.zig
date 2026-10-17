//A game enum: put it on an object with an EnumComponent, which picks one of its values. Import it by this file's
//name, @import("EnumName"), and read or change it from a script with comp.Get(EnumName) and comp.Set(EnumName.First).
//Keep the enum's name the same as the file's: the editor finds it by that name
pub const EnumName = enum {
    First,
    Second,
};
