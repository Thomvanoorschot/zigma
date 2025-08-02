const std = @import("std");
const OrderbookLevel = @import("orderbook_level.zig").OrderbookLevel;
const backstage = @import("backstage");
const zbor = backstage.zbor;

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

    pub fn processLevelUpdates(orderbook: *Self, bids: []const OrderbookLevel, asks: []const OrderbookLevel) !void {
        for (bids) |bid| {
            try updateOrderbook(orderbook, bid.price, bid.qty, true);
        }

        for (asks) |ask| {
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

    pub fn print(self: *const Self) void {
        std.debug.print("\n=== ORDERBOOK ===\n", .{});
        std.debug.print("Exchange: {s}\n", .{self.exchange});
        std.debug.print("Ticker: {s}\n", .{self.ticker});
        std.debug.print("Max Depth: {d}\n\n", .{self.max_depth});

        const max_levels = @max(self.bids.items.len, self.asks.items.len);

        if (max_levels == 0) {
            std.debug.print("No orderbook data available\n", .{});
            return;
        }

        std.debug.print("{s:>12} {s:>12} | {s:>12} {s:>12}\n", .{ "BID QTY", "BID PRICE", "ASK PRICE", "ASK QTY" });
        std.debug.print("{s:-<12} {s:-<12}-+-{s:-<12} {s:-<12}\n", .{ "", "", "", "" });

        var i: usize = 0;
        while (i < max_levels) : (i += 1) {
            if (i < self.bids.items.len and i < self.asks.items.len) {
                std.debug.print("{d:>12.6} {d:>12.2} | {d:>12.2} {d:>12.6}\n", .{
                    self.bids.items[i].qty,
                    self.bids.items[i].price,
                    self.asks.items[i].price,
                    self.asks.items[i].qty,
                });
            } else if (i < self.bids.items.len) {
                std.debug.print("{d:>12.6} {d:>12.2} | {s:>12} {s:>12}\n", .{
                    self.bids.items[i].qty,
                    self.bids.items[i].price,
                    "",
                    "",
                });
            } else if (i < self.asks.items.len) {
                std.debug.print("{s:>12} {s:>12} | {d:>12.2} {d:>12.6}\n", .{
                    "",
                    "",
                    self.asks.items[i].price,
                    self.asks.items[i].qty,
                });
            }
        }

        std.debug.print("\n", .{});
    }

    pub fn cborStringify(self: Self, o: zbor.Options, out: anytype) !void {
        try zbor.builder.writeMap(out, 5);

        try zbor.builder.writeTextString(out, "bids");
        try zbor.stringify(self.bids.items, .{ .allocator = o.allocator }, out);

        try zbor.builder.writeTextString(out, "asks");
        try zbor.stringify(self.asks.items, .{ .allocator = o.allocator }, out);

        try zbor.builder.writeTextString(out, "max_depth");
        try zbor.stringify(self.max_depth, .{}, out);

        try zbor.builder.writeTextString(out, "exchange");
        try zbor.builder.writeTextString(out, self.exchange);

        try zbor.builder.writeTextString(out, "ticker");
        try zbor.builder.writeTextString(out, self.ticker);
    }

    pub fn cborParse(item: anytype, options: zbor.Options) !Self {
        var map = if (item.map()) |m| m else return error.UnexpectedItem;

        const allocator = options.allocator orelse return error.AllocatorRequired;
        var result = Self{
            .bids = std.ArrayList(OrderbookLevel).init(allocator),
            .asks = std.ArrayList(OrderbookLevel).init(allocator),
            .max_depth = 0,
            .exchange = "",
            .ticker = "",
        };

        while (map.next()) |kv| {
            const key_str = if (kv.key.string()) |s| s else continue;
            if (std.mem.eql(u8, key_str, "bids")) {
                const bids_slice = try zbor.parse([]const OrderbookLevel, kv.value, options);
                try result.bids.appendSlice(bids_slice);
                allocator.free(bids_slice);
            } else if (std.mem.eql(u8, key_str, "asks")) {
                const asks_slice = try zbor.parse([]const OrderbookLevel, kv.value, options);
                try result.asks.appendSlice(asks_slice);
                allocator.free(asks_slice);
            } else if (std.mem.eql(u8, key_str, "max_depth")) {
                result.max_depth = try zbor.parse(u32, kv.value, options);
            } else if (std.mem.eql(u8, key_str, "exchange")) {
                result.exchange = try zbor.parse([]const u8, kv.value, options);
            } else if (std.mem.eql(u8, key_str, "ticker")) {
                result.ticker = try zbor.parse([]const u8, kv.value, options);
            }
        }

        return result;
    }
};
