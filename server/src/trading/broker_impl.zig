const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");
const ob = @import("orderbook.zig");
const ohlcu = @import("ohlc_update.zig");
const Loop = backstage.xev.Loop;
const Context = backstage.Context;
const OrderbookUpdate = ob.OrderbookUpdate;
const OHLCUpdate = ohlcu.OHLCUpdate;

pub const BrokerType = enum {
    kraken,
};

pub const BrokerPayloadType = enum {
    orderbook_update,
    ohlc_update,
};

pub const BrokerPayload = union(BrokerPayloadType) {
    orderbook_update: *OrderbookUpdate,
    ohlc_update: *OHLCUpdate,
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

    pub fn subscribeToOHLC(self: *Self, ticker: []const u8) !void {
        switch (self.*) {
            inline else => |broker| return try broker.subscribeToOHLC(ticker),
        }
    }
};
