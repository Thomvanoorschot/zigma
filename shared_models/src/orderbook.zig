const std = @import("std");
const Allocator = std.mem.Allocator;
const zbor = @import("zbor");
const zborParse = zbor.parse;
const zborStringify = zbor.stringify;
const DataItem = zbor.DataItem;

fn priceDescending(_: void, a: [2]f64, b: [2]f64) bool {
    return a[0] > b[0];
}

fn priceAscending(_: void, a: [2]f64, b: [2]f64) bool {
    return a[0] < b[0];
}

pub fn parseOrderbook(allocator: Allocator, str: []const u8) !*const OrderBook {
    const di = try DataItem.new(str);
    const ob = try zborParse(*OrderBook, di, .{ .allocator = allocator });
    return ob;
}

pub const OrderBook = struct {
    bids: std.ArrayList([2]f64),
    asks: std.ArrayList([2]f64),
    max_depth: usize,
    exchange: []const u8,
    ticker: []const u8,

    const Self = @This();
    pub fn init(allocator: Allocator, exchange: []const u8, ticker: []const u8, depth: usize) !OrderBook {
        return OrderBook{
            .bids = try std.ArrayList([2]f64).initCapacity(allocator, depth + 1),
            .asks = try std.ArrayList([2]f64).initCapacity(allocator, depth + 1),
            .max_depth = depth,
            .exchange = try allocator.dupe(u8, exchange),
            .ticker = try allocator.dupe(u8, ticker),
        };
    }

    pub fn stringify(self: *Self, allocator: Allocator) !std.ArrayList(u8) {
        var str = std.ArrayList(u8).init(allocator);
        try zborStringify(self, .{
            .ignore_override = true,
            .field_settings = &.{
                .{ .name = "allocator", .field_options = .{ .skip = .Skip } },
            },
        }, str.writer());
        return str;
    }

    pub fn update(self: *Self, price: f64, qty: f64, is_bid: bool) !void {
        var levels = if (is_bid) &self.bids else &self.asks;
        var is_update = false;
        for (levels.items, 0..) |level, i| {
            if (std.math.approxEqAbs(f64, level[0], price, 1e-12)) {
                if (qty == 0) {
                    _ = levels.swapRemove(i);
                } else {
                    levels.items[i] = .{ price, qty };
                }
                is_update = true;
            }
        }
        if (!is_update) {
            try levels.append(.{ price, qty });
        }
        if (is_bid) {
            std.mem.sort([2]f64, levels.items, {}, comptime priceDescending);
        } else {
            std.mem.sort([2]f64, levels.items, {}, comptime priceAscending);
        }

        if (levels.items.len > self.max_depth) {
            try levels.resize(self.max_depth);
        }
    }

    pub fn processUpdates(self: *Self, bids: []const [2]f64, asks: []const [2]f64) !void {
        for (bids) |bid| {
            try self.update(bid[0], bid[1], true);
        }

        for (asks) |ask| {
            try self.update(ask[0], ask[1], false);
        }
    }

    pub fn display(self: *const Self) void {
        std.debug.print("\n=== Order Book {s} {s} ===\n", .{ self.exchange, self.ticker });

        std.debug.print("\nAsks (Sell Orders):\n", .{});
        const display_ask_count = @min(self.max_depth, self.asks.items.len);
        for (0..display_ask_count) |j| {
            const level = self.asks.items[j];
            std.debug.print("€{d:.2} - {d:.8}\n", .{ level.price, level.qty });
        }

        std.debug.print("\nBids (Buy Orders):\n", .{});
        const display_bid_count = @min(self.max_depth, self.bids.items.len);
        for (0..display_bid_count) |j| {
            const level = self.bids.items[j];
            std.debug.print("€{d:.2} - {d:.8}\n", .{ level.price, level.qty });
        }

        std.debug.print("\n======================\n", .{});
        std.debug.print("length bids: {d} length asks: {d}\n", .{ self.bids.items.len, self.asks.items.len });
    }
};
