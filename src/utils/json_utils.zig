const std = @import("std");

pub fn jsonMarshalFixedBuffer(req: anytype, buffer: []u8) ![]u8 {
    var stream = std.io.fixedBufferStream(buffer);
    const writer = stream.writer();

    try std.json.stringify(req, .{}, writer);
    return stream.getWritten();
}

pub fn jsonUnmarshal(comptime T: type, allocator: std.mem.Allocator, buffer: []u8) !T {
    const parsed = try std.json.parseFromSlice(
        T,
        allocator,
        buffer,
        .{},
    );
    defer parsed.deinit();

    return parsed.value;
}
