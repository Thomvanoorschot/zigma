const std = @import("std");

pub fn frameHeader(comptime UserFrameType: type) type {
    comptime {
        const info = @typeInfo(UserFrameType);
        if (info != .Enum) {
            @compileError("UserFrameType must be an enum.");
        }
        if (info.Enum.tag_type != u8) {
            @compileError("UserFrameType enum must be backed by u8.");
        }
    }

    return packed struct {
        type: UserFrameType,
        payload_len: u32,

        pub const HEADER_SIZE = @sizeOf(@This());
    };
}
