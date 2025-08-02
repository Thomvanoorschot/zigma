const std = @import("std");
const OrderbookLevel = @import("orderbook_level.zig").OrderbookLevel;

pub const Orderbook = struct {
    bids: std.ArrayList(OrderbookLevel),
    asks: std.ArrayList(OrderbookLevel),
    max_depth: u32,
    exchange: []const u8,
    ticker: []const u8,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .bids = std.ArrayList(OrderbookLevel).init(allocator),
            .asks = std.ArrayList(OrderbookLevel).init(allocator),
            .max_depth = 0,
            .exchange = "",
            .ticker = "",
        };
    }
    pub fn deinit(self: *Self) void {
        self.bids.deinit();
        self.asks.deinit();
    }

    const Self = @This();

    pub fn processLevelUpdates(orderbook: *Self, bids: std.ArrayList(OrderbookLevel), asks: std.ArrayList(OrderbookLevel)) !void {
        for (bids.items) |bid| {
            try updateOrderbook(orderbook, bid.price, bid.qty, true);
        }

        for (asks.items) |ask| {
            try updateOrderbook(orderbook, ask.price, ask.qty, false);
        }
    }
    fn updateOrderbook(orderbook: *Self, price: f64, qty: f64, is_bid: bool) !void {
        var levels = if (is_bid) &orderbook.bids else &orderbook.asks;
        var is_update = false;
        for (levels.items, 0..) |level, i| {
            if (std.math.approxEqAbs(f64, level.price, price, 1e-12)) {
                if (qty == 0) {
                    _ = levels.swapRemove(i);
                } else {
                    levels.items[i] = .{ .price = price, .qty = qty };
                }
                is_update = true;
            }
        }
        if (!is_update) {
            try levels.append(.{ .price = price, .qty = qty });
        }
        if (is_bid) {
            std.mem.sort(OrderbookLevel, levels.items, {}, comptime priceDescending);
        } else {
            std.mem.sort(OrderbookLevel, levels.items, {}, comptime priceAscending);
        }

        if (levels.items.len > orderbook.max_depth) {
            try levels.resize(orderbook.max_depth);
        }
    }
    fn priceDescending(_: void, a: OrderbookLevel, b: OrderbookLevel) bool {
        return a.price > b.price;
    }

    fn priceAscending(_: void, a: OrderbookLevel, b: OrderbookLevel) bool {
        return a.price < b.price;
    }
};
