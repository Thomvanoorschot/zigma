const std = @import("std");
const krkn = @import("exchanges/kraken/broker.zig");
const backstage = @import("backstage");
const OrderbookUpdate = @import("types/orderbook_update.zig").OrderbookUpdate;
const OHLCUpdate = @import("types/ohlc_update.zig").OHLCUpdate;

const Loop = backstage.xev.Loop;
const Context = backstage.Context;

pub const BrokerType = enum {
    KRAKEN,
};

pub const MarketDataType = enum {
    ORDERBOOK,
    OHLC,
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
    KRAKEN: *krkn.Broker,
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
            .KRAKEN => {
                return .{ .KRAKEN = try krkn.Broker.init(
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
            inline else => |broker| broker.deinit(),
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
