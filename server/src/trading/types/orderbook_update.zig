const std = @import("std");
const OrderbookLevel = @import("orderbook_level.zig").OrderbookLevel;

pub const OrderbookUpdate = struct {
    ticker: []const u8,
    bids: []const OrderbookLevel,
    asks: []const OrderbookLevel,
    checksum: u64,
    timestamp: ?[]const u8 = null,
};