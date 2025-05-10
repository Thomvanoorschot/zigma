const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const orderbook_actor = @import("orderbook_actor.zig");
const ohlcu = @import("ohlc_update.zig");
const obu = @import("orderbook_update.zig");
const ohlc_actor = @import("ohlc_actor.zig");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;
const xev = backstage.xev;
const Context = backstage.Context;
const BrokerImpl = brkr_impl.BrokerImpl;
const BrokerType = brkr_impl.BrokerType;
const BrokerPayload = brkr_impl.BrokerPayload;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const OrderbookMessage = orderbook_actor.OrderbookMessage;
const OrderbookUpdate = obu.OrderbookUpdate;
const OHLCUpdate = ohlcu.OHLCUpdate;
const OHLCMessage = ohlc_actor.OHLCMessage;
pub const BrokerMessage = union(enum) {
    init: BrokerInitRequest,
    orderbook_subscribe: BrokerSubscribeRequest,
    ohlc_subscribe: BrokerSubscribeRequest,
};

pub const BrokerInitRequest = struct {
    broker: BrokerType,
};

pub const BrokerSubscribeRequest = struct {
    ticker: []const u8,
};

pub const BrokerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    broker: ?BrokerImpl = null,
    // TODO: This currently limits to a single subscriber per ticker, need to change this
    orderbook_subscriptions: std.StringHashMap(*ActorInterface),
    ohlc_subscriptions: std.StringHashMap(*ActorInterface),
    completion: xev.Completion = undefined,

    const Self = @This();
    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .orderbook_subscriptions = std.StringHashMap(*ActorInterface).init(allocator),
            .ohlc_subscriptions = std.StringHashMap(*ActorInterface).init(allocator),
        };

        return self;
    }

    pub fn deinit(self: *Self) !void {
        try self.ctx.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(BrokerMessage)) !void {
        switch (message.payload) {
            .init => |m| {
                self.broker = try BrokerImpl.init(
                    self.allocator,
                    self.ctx.getLoop(),
                    m.broker,
                    @ptrCast(self),
                    readMessage,
                );
            },
            .orderbook_subscribe => |m| {
                // TODO Split this up into seperate messages?
                try self.broker.?.subscribeToOrderbook(m.ticker);
                try self.orderbook_subscriptions.put(m.ticker, message.sender.?);
            },
            .ohlc_subscribe => |m| {
                try self.broker.?.subscribeToOHLC(m.ticker);
                try self.ohlc_subscriptions.put(m.ticker, message.sender.?);
            },
        }
    }

    fn readMessage(context: *anyopaque, message: anyerror!?BrokerPayload) !void {
        const self = unsafeAnyOpaqueCast(Self, context);

        if (try message) |m| {
            switch (m) {
                .orderbook_update => |update| {
                    if (self.orderbook_subscriptions.get(update.data.symbol)) |subscriber| {
                        try subscriber.send(self.ctx.actor, OrderbookMessage{
                            .orderbook_update = update,
                        });
                    }
                },
                .ohlc_update => |update| {
                    if (self.ohlc_subscriptions.get(update.data.symbol)) |subscriber| {
                        try subscriber.send(self.ctx.actor, OHLCMessage{
                            .ohlc_update = update,
                        });
                    }
                },
            }
        }
    }
};
