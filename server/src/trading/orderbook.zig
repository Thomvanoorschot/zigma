const std = @import("std");
const Allocator = std.mem.Allocator;
const shared_models = @import("shared_models");
const Orderbook = shared_models.Orderbook;

pub fn update(ob: *Orderbook, price: f64, qty: f64, is_bid: bool) !void {
    var levels = if (is_bid) &ob.bids else &ob.asks;
    var is_update = false;
    for (levels.items, 0..) |level, i| {
        if (std.math.approxEqAbs(f64, level.price, price, 1e-12)) {
            if (qty == 0) {
                _ = levels.swapRemove(i);
            } else {
                levels.items[i] = .{ .price = price, .quantity = qty };
            }
            is_update = true;
        }
    }
    if (!is_update) {
        try levels.append(.{ .price = price, .quantity = qty });
    }
    if (is_bid) {
        std.mem.sort(shared_models.Level, levels.items, {}, comptime priceDescending);
    } else {
        std.mem.sort(shared_models.Level, levels.items, {}, comptime priceAscending);
    }

    if (levels.items.len > ob.max_depth) {
        try levels.resize(ob.max_depth);
    }
}

pub fn processUpdates(ob: *Orderbook, bids: []const [2]f64, asks: []const [2]f64) !void {
    for (bids) |bid| {
        try update(ob, bid[0], bid[1], true);
    }

    for (asks) |ask| {
        try update(ob, ask[0], ask[1], false);
    }
}

pub const OrderbookUpdate = struct {
    arena_state: std.heap.ArenaAllocator,
    symbol: []const u8,
    bids: [][2]f64,
    asks: [][2]f64,
    checksum: u64,
    timestamp: ?[]const u8 = null,

    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        args: struct {
            symbol: []const u8,
            bids: []const [2]f64,
            asks: []const [2]f64,
            checksum: u64,
            timestamp: ?[]const u8 = null,
        },
    ) !*Self {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        const self = try allocator.create(Self);
        var arena = arena_state.allocator();
        const symbol = try arena.dupe(u8, args.symbol);

        var bids = try arena.alloc([2]f64, args.bids.len);
        for (args.bids, 0..) |bid, bid_idx| {
            bids[bid_idx] = .{ bid[0], bid[1] };
        }

        var asks = try arena.alloc([2]f64, args.asks.len);
        for (args.asks, 0..) |ask, ask_idx| {
            asks[ask_idx] = .{ ask[0], ask[1] };
        }
        const timestamp = if (args.timestamp) |ts| try arena.dupe(u8, ts) else null;

        self.* = .{
            .arena_state = arena_state,
            .symbol = symbol,
            .bids = bids,
            .asks = asks,
            .checksum = args.checksum,
            .timestamp = timestamp,
        };
        return self;
    }

    pub fn deinit(self: Self) void {
        self.arena_state.deinit();
    }
};

fn priceDescending(_: void, a: shared_models.Level, b: shared_models.Level) bool {
    return a.price > b.price;
}

fn priceAscending(_: void, a: shared_models.Level, b: shared_models.Level) bool {
    return a.price < b.price;
}
