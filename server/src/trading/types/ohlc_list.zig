const std = @import("std");
const ArrayList = std.ArrayList;
const OHLC = @import("ohlc.zig").OHLC;

pub const OHLCList = struct {
    ticker: []const u8,
    ohlc: ArrayList(OHLC),

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .ticker = "",
            .ohlc = ArrayList(OHLC).init(allocator),
        };
    }
};
