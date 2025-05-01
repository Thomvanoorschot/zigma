const std = @import("std");
const Allocator = std.mem.Allocator;
const zbor = @import("zbor");
const zborParse = zbor.parse;
const zborStringify = zbor.stringify;
const DataItem = zbor.DataItem;

fn priceDescending(_: void, a: PriceLevel, b: PriceLevel) bool {
    return a.price > b.price;
}

fn priceAscending(_: void, a: PriceLevel, b: PriceLevel) bool {
    return a.price < b.price;
}

pub const PriceLevel = struct {
    price: f64,
    qty: f64,
};

pub fn parseOrderbook(allocator: Allocator, str: []const u8) !*const OrderBook {
    const di = try DataItem.new(str);
    const ob = try zborParse(*OrderBook, di, .{ .allocator = allocator });
    return ob;
}

pub const OrderBook = struct {
    bids: std.ArrayList(PriceLevel),
    asks: std.ArrayList(PriceLevel),
    max_depth: usize,
    exchange: []const u8,
    ticker: []const u8,
    allocator: Allocator,

    const Self = @This();
    pub fn init(allocator: Allocator, exchange: []const u8, ticker: []const u8, depth: usize) !OrderBook {
        return OrderBook{
            .bids = try std.ArrayList(PriceLevel).initCapacity(allocator, depth + 1),
            .asks = try std.ArrayList(PriceLevel).initCapacity(allocator, depth + 1),
            .max_depth = depth,
            .exchange = try allocator.dupe(u8, exchange),
            .ticker = try allocator.dupe(u8, ticker),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.bids);
        self.allocator.free(self.asks);
        self.allocator.free(self.exchange);
        self.allocator.free(self.ticker);
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
            std.mem.sort(PriceLevel, levels.items, {}, comptime priceDescending);
        } else {
            std.mem.sort(PriceLevel, levels.items, {}, comptime priceAscending);
        }

        if (levels.items.len > self.max_depth) {
            try levels.resize(self.max_depth);
        }
    }

    pub fn processUpdates(self: *Self, bids: []const PriceLevel, asks: []const PriceLevel) !void {
        for (bids) |bid| {
            try self.update(bid.price, bid.qty, true);
        }

        for (asks) |ask| {
            try self.update(ask.price, ask.qty, false);
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
