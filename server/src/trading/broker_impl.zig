const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");
const actor_message = @import("../actor_message/actor_message.pb.zig");
const broker_proto = @import("../actor_message/broker.pb.zig");
const orderbook_proto = @import("../actor_message/orderbook.pb.zig");
const ohlc_proto = @import("../actor_message/ohlc.pb.zig");

const Loop = backstage.xev.Loop;
const Context = backstage.Context;
const BrokerType = broker_proto.BrokerType;
const OrderbookUpdate = orderbook_proto.OrderbookUpdate;
const OHLCUpdate = ohlc_proto.OHLCUpdate;

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
            else => return error.UnsupportedBroker,
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
