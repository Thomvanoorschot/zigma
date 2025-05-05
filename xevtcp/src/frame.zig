const std = @import("std");

const headerSize = @sizeOf(u8) + @sizeOf(u32);

pub const Frame = struct {
    payload: []u8,

    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        msg_type: u8,
        payload: []u8,
    ) ![]u8 {
        const totalSize = headerSize + payload.len;

        var buf = try allocator.alloc(u8, totalSize);
        buf[0] = msg_type;

        std.mem.writeInt(u32, buf[1..headerSize], @intCast(payload.len), .big);
        @memcpy(buf[headerSize..], payload);
        return buf;
    }
};

pub const FrameHeader = struct {
    header_bytes: [headerSize]u8,

    pub fn messageType(self: FrameHeader) u8 {
        return self.header_bytes[0];
    }
    pub fn payloadLength(self: FrameHeader) u32 {
        return std.mem.readInt(u32, self.header_bytes[1..headerSize], .big);
    }
};
