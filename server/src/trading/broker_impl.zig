const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");

const Loop = backstage.xev.Loop;
const Context = backstage.Context;

pub const BrokerType = enum {
    kraken,
};

pub const BrokerPayloadType = enum {
    orderbook_update,
};

pub const BrokerPayload = union(BrokerPayloadType) {
    orderbook_update: OrderbookUpdate,
};

pub const OrderbookUpdate = struct {
    arena_state: std.heap.ArenaAllocator,
    data: *UpdateData,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        return Self{
            .arena_state = arena_state,
            .data = try arena_state.allocator().create(UpdateData),
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
    checksum: u64,
    timestamp: ?[]const u8 = null,
};

pub const BrokerImpl = union(BrokerType) {
    kraken: *krkn.Broker,
    // Add more brokers as needed
    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        loop: *Loop,
        broker_type: BrokerType,
        callback_context: *anyopaque,
        comptime read_callback: *const fn (*anyopaque, anyerror!?BrokerPayload) anyerror!void,
    ) !Self {
        switch (broker_type) {
            .kraken => {
                return .{ .kraken = try krkn.Broker.init(
                    allocator,
                    loop,
                    callback_context,
                    read_callback,
                ) };
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
};
