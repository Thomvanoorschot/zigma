const std = @import("std");
const brkr_impl = @import("broker_impl.zig");
const Allocator = std.mem.Allocator;
const OrderbookUpdate = brkr_impl.OrderbookUpdate;
const PriceLevel = brkr_impl.PriceLevel;

fn priceAscending(_: void, a: PriceLevel, b: PriceLevel) bool {
    return a.price < b.price;
}

fn priceDescending(_: void, a: PriceLevel, b: PriceLevel) bool {
    return a.price > b.price;
}

pub const OrderBook = struct {
    bids: []PriceLevel,
    bid_count: usize,
    asks: []PriceLevel,
    ask_count: usize,
    max_depth: usize,
    exchange: []const u8,
    ticker: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator, exchange: []const u8, ticker: []const u8, depth: usize) !OrderBook {
        var bids = try allocator.alloc(PriceLevel, depth);
        var asks = try allocator.alloc(PriceLevel, depth);

        for (0..depth) |i| {
            bids[i] = .{ .price = 0.0, .qty = 0.0 };
            asks[i] = .{ .price = 0.0, .qty = 0.0 };
        }

        return OrderBook{
            .bids = bids,
            .bid_count = 0,
            .asks = asks,
            .ask_count = 0,
            .max_depth = depth,
            .exchange = try allocator.dupe(u8, exchange),
            .ticker = try allocator.dupe(u8, ticker),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OrderBook) void {
        self.allocator.free(self.bids);
        self.allocator.free(self.asks);
        self.allocator.free(self.exchange);
        self.allocator.free(self.ticker);
    }

    pub fn update(self: *OrderBook, price: f64, qty: f64, is_bid: bool) void {
        if (std.math.isNan(price) or std.math.isNan(qty)) {
            std.debug.print("Warning: NaN values detected in orderbook update\n", .{});
            return;
        }

        var levels = if (is_bid) self.bids else self.asks;
        const count = if (is_bid) &self.bid_count else &self.ask_count;

        for (0..count.*) |i| {
            if (std.math.approxEqAbs(f64, levels[i].price, price, 0.0000001)) {
                if (qty <= 0.0) {
                    self.removeLevel(is_bid, i);
                } else {
                    levels[i].qty = qty;
                }
                return;
            }
        }

        if (qty <= 0.0) return;

        if (count.* < self.max_depth) {
            levels[count.*] = .{ .price = price, .qty = qty };
            count.* += 1;
            
            self.sortLevels(is_bid);
        } else {
            const should_replace = if (is_bid) 
                price > self.bids[count.* - 1].price
            else
                price < self.asks[count.* - 1].price;

            if (should_replace) {
                levels[count.* - 1] = .{ .price = price, .qty = qty };
                self.sortLevels(is_bid);
            }
        }
    }

    pub fn processUpdates(self: *OrderBook, bids: []const PriceLevel, asks: []const PriceLevel) void {
        for (bids) |bid| {
            self.update(bid.price, bid.qty, true);
        }

        for (asks) |ask| {
            self.update(ask.price, ask.qty, false);
        }

        if (self.bid_count > self.max_depth) {
            self.bid_count = self.max_depth;
        }

        if (self.ask_count > self.max_depth) {
            self.ask_count = self.max_depth;
        }
    }

    fn removeLevel(self: *OrderBook, is_bid: bool, index: usize) void {
        var levels = if (is_bid) self.bids else self.asks;
        const count = if (is_bid) &self.bid_count else &self.ask_count;

        if (index >= count.*) return;

        for (index..count.* - 1) |i| {
            levels[i] = levels[i + 1];
        }

        count.* -= 1;
    }

    fn sortLevels(self: *OrderBook, is_bid: bool) void {
        if (is_bid) {
            std.sort.pdq(PriceLevel, self.bids[0..self.bid_count], {}, priceDescending);
        } else {
            std.sort.pdq(PriceLevel, self.asks[0..self.ask_count], {}, priceAscending);
        }
    }

    pub fn getMidPrice(self: *const OrderBook) ?f64 {
        if (self.bid_count == 0 or self.ask_count == 0) return null;

        const best_bid = self.bids[0].price;
        const best_ask = self.asks[0].price;

        return (best_bid + best_ask) / 2.0;
    }

    pub fn getBestBid(self: *const OrderBook) ?PriceLevel {
        if (self.bid_count == 0) return null;
        return self.bids[0];
    }

    pub fn getBestAsk(self: *const OrderBook) ?PriceLevel {
        if (self.ask_count == 0) return null;
        return self.asks[0];
    }

    pub fn display(self: *const OrderBook) void {
        std.debug.print("\n=== Order Book {s} {s} ===\n", .{ self.exchange, self.ticker });

        std.debug.print("\nAsks (Sell Orders):\n", .{});
        const display_ask_count = @min(self.max_depth, self.ask_count);
        var i: usize = display_ask_count;
        while (i > 0) : (i -= 1) {
            const level = self.asks[i - 1];
            std.debug.print("€{d:.2} - {d:.8}\n", .{ level.price, level.qty });
        }

        std.debug.print("\nBids (Buy Orders):\n", .{});
        const display_bid_count = @min(self.max_depth, self.bid_count);
        for (0..display_bid_count) |j| {
            const level = self.bids[j];
            std.debug.print("€{d:.2} - {d:.8}\n", .{ level.price, level.qty });
        }

        std.debug.print("\n======================\n", .{});
        std.debug.print("length bids: {d} length asks: {d}\n", .{ self.bids.len, self.asks.len });
    }

    pub fn calculateChecksum(self: *const OrderBook) u32 {
        var checksum_buffer = std.ArrayList(u8).init(self.allocator);
        defer checksum_buffer.deinit();

        const checksum_depth = 10;

        const bid_levels = @min(checksum_depth, self.bid_count);
        for (0..bid_levels) |i| {
            const level = self.bids[i];
            const price_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{level.price}) catch continue;
            defer self.allocator.free(price_str);

            const qty_str = std.fmt.allocPrint(self.allocator, "{d:.8}", .{level.qty}) catch continue;
            defer self.allocator.free(qty_str);

            checksum_buffer.appendSlice(price_str) catch continue;
            checksum_buffer.append(':') catch continue;
            checksum_buffer.appendSlice(qty_str) catch continue;
            checksum_buffer.append(':') catch continue;
        }

        const ask_levels = @min(checksum_depth, self.ask_count);
        for (0..ask_levels) |i| {
            const level = self.asks[i];
            const price_str = std.fmt.allocPrint(self.allocator, "{d:.1}", .{level.price}) catch continue;
            defer self.allocator.free(price_str);

            const qty_str = std.fmt.allocPrint(self.allocator, "{d:.8}", .{level.qty}) catch continue;
            defer self.allocator.free(qty_str);

            checksum_buffer.appendSlice(price_str) catch continue;
            checksum_buffer.append(':') catch continue;
            checksum_buffer.appendSlice(qty_str) catch continue;
            checksum_buffer.append(':') catch continue;
        }

        const checksum_str = checksum_buffer.items;
        var hasher = std.hash.Crc32.init();
        hasher.update(checksum_str);
        return hasher.final();
    }
};

pub fn updateOrderbook(
    orderbook: *OrderBook,
    data: OrderbookUpdate,
) !bool {
    orderbook.processUpdates(data.data.bids, data.data.asks);
    return true;
}
