const std = @import("std");
const ArrayList = std.ArrayList;
const OrderbookLevel = @import("orderbook_level.zig").OrderbookLevel;

pub const OrderbookUpdate = struct {
    ticker: []const u8,
    bids: ArrayList(OrderbookLevel),
    asks: ArrayList(OrderbookLevel),
    checksum: u64,
    timestamp: ?[]const u8 = null,
};
