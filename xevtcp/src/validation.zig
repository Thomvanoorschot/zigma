pub fn validateMessageCallbacks(comptime MessageCallbacks: type) void {
    const info = @typeInfo(MessageCallbacks);
    comptime if (info != .@"union") {
        @compileError("MessageTypeUnion must be a union");
    };
    comptime if (info.@"union".tag_type == null) {
        @compileError("MessageTypeUnion must be a tagged union");
    };
    inline for (info.@"union".fields) |field| {
        const field_type_info = @typeInfo(field.type);
        comptime if (field_type_info != .pointer) {
            @compileError("Field '" ++ field.name ++ "' in MessageCallbacks must be a function pointer, found '" ++ @typeName(field.type) ++ "'");
        };

        const func_type = field_type_info.pointer.child;
        const func_type_info = @typeInfo(func_type);

        comptime if (func_type_info != .@"fn") {
            @compileError("Field '" ++ field.name ++ "' in MessageCallbacks must point to a function, but points to '" ++ @typeName(func_type) ++ "'");
        };

        const fn_info = func_type_info.@"fn";
        comptime if (fn_info.return_type.? != anyerror!void) {
            @compileError("Callback function type for '" ++ field.name ++ "' must return 'anyerror!void', found '" ++ @typeName(fn_info.return_type.?) ++ "'");
        };
        comptime if (fn_info.params.len != 2) {
            @compileError("Callback function type for '" ++ field.name ++ "' must take 2 arguments, found " ++ @tagName(fn_info.params.len));
        };
        comptime if (fn_info.params[0].type.? != *anyopaque) {
            @compileError("First argument of callback function type for '" ++ field.name ++ "' must be '*anyopaque', found '" ++ @typeName(fn_info.params[0].type.?) ++ "'");
        };
        comptime if (fn_info.params[1].type.? != []const u8) {
            @compileError("Second argument of callback function type for '" ++ field.name ++ "' must be '[]const u8', found '" ++ @typeName(fn_info.params[1].type.?) ++ "'");
        };
    }
}
