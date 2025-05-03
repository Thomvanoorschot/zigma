const std = @import("std");

pub fn ReadBuffers(comptime U: type) type {
    const union_fields = @typeInfo(U).@"union".fields;
    var fields_array: [union_fields.len]std.builtin.Type.StructField = undefined;

    inline for (union_fields, 0..) |field, i| {
        fields_array[i] = .{
            .name = field.name,
            // TODO This is obviously not the best way to do this
            .type = [20000]u8,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf([4096]u8),
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