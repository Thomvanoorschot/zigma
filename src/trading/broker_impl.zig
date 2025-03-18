const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const alphazig = @import("alphazig");

const concurrency = alphazig.concurrency;
const Context = alphazig.Context;
const Coroutine = concurrency.Coroutine;

pub const BrokerType = enum {
    kraken,
};

pub const BrokerMessageType = enum {
    orderbook_update,
};

pub const BrokerMessage = union(BrokerMessageType) {
    orderbook_update: OrderbookUpdate,
};

pub const OrderbookUpdate = struct {
    arena_state: std.heap.ArenaAllocator,
    data: []UpdateData,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, count: usize) !Self {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        return Self{
            .arena_state = arena_state,
            .data = try arena_state.allocator().alloc(UpdateData, count),
        };
    }

    pub fn deinit(self: Self) void {
        self.arena_state.deinit();
    }
};

pub const PriceLevel = struct {
    price: f64,
    qty: f64,
};

pub const UpdateData = struct {
    symbol: []const u8,
    bids: []const PriceLevel,
    asks: []const PriceLevel,
    timestamp: ?[]const u8 = null,
};

pub const BrokerImpl = union(BrokerType) {
    kraken: *krkn.Broker,
    // Add more brokers as needed
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, broker_type: BrokerType) !Self {
        switch (broker_type) {
            .kraken => {
                return .{ .kraken = try krkn.Broker.init(allocator) };
            },
        }
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            inline else => |*broker| broker.deinit(),
        }
    }

    pub fn subscribeToOrderbook(self: *Self, ticker: []const u8) !void {
        switch (self.*) {
            inline else => |broker| return try broker.subscribeToOrderbook(ticker),
        }
    }
    pub fn readMessage(self: *Self) !?BrokerMessage {
        switch (self.*) {
            inline else => |broker| return try broker.readMessage(),
        }
    }
};
