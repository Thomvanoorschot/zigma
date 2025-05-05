const std = @import("std");
const frm = @import("frame.zig");
const Frame = frm.Frame;
const FrameHeader = frm.FrameHeader;
pub fn ReadBuffers(comptime U: type) type {
    const union_fields = @typeInfo(U).@"enum".fields;
    var fields_array: [union_fields.len]std.builtin.Type.StructField = undefined;

    inline for (union_fields, 0..) |field, i| {
        fields_array[i] = .{
            .name = field.name,
            .type = Frame,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Frame),
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
