const std = @import("std");

pub fn Callbacks(comptime U: type) type {
    const union_fields = @typeInfo(U).@"union".fields;
    var fields_array: [union_fields.len]std.builtin.Type.StructField = undefined;

    inline for (union_fields, 0..) |field, i| {
        fields_array[i] = .{
            .name = field.name,
            .type = field.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(field.type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields_array,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}
