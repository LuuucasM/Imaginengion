pub fn Quat(comptime number_type: type) type {
    _ValidateNumberType(number_type);
    return packed struct {
        const Self = @This();
        w: number_type,
        x: number_type,
        y: number_type,
        z: number_type,
    };
}

pub fn _ValidateNumberType(comptime number_type: type) void {
    const type_info = @typeInfo(number_type);
    if (type_info != .int and type_info != .comptime_int and type_info != .float and type_info != .comptime_float) {
        @compileError(@typeName(number_type) ++ "vector type must be an int/float type");
    }
}
