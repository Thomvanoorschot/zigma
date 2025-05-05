const std = @import("std");

pub const Frame = struct {
    pub fn init(
        allocator: std.mem.Allocator,
        msg_type: u8,
        payload: []const u8,
    ) ![]u8 {
        const headerSize = 1 + @sizeOf(u32);
        const totalSize = headerSize + payload.len;

        var buf = try allocator.alloc(u8, totalSize);
        buf[0] = msg_type;

        std.mem.writeInt(u32, buf[1..headerSize], @intCast(payload.len), .big);
        @memcpy(buf[headerSize..], payload);
        return buf;
    }
};
