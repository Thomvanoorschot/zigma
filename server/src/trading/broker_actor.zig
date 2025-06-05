const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const orderbook_actor = @import("orderbook_actor.zig");
const ohlc_actor = @import("ohlc_actor.zig");
const shared_models = @import("shared_models");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

const xev = backstage.xev;
const Context = backstage.Context;
const BrokerImpl = brkr_impl.BrokerImpl;
const BrokerType = brkr_impl.BrokerType;
const BrokerPayload = brkr_impl.BrokerPayload;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const BrokerActorMessage = shared_models.BrokerActor.message_union;
const OrderbookActorMessage = shared_models.OrderbookActor.message_union;
const OHLCActorMessage = shared_models.OHLCActor.message_union;

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

    pub fn receive(self: *Self, message: *const Envelope(BrokerActorMessage)) !void {
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
                try self.broker.?.subscribeToOrderbook(m.ticker.Owned.str);
                try self.orderbook_subscriptions.put(m.ticker.Owned.str, message.sender.?);
            },
            .ohlc_subscribe => |m| {
                try self.broker.?.subscribeToOHLC(m.ticker.Owned.str);
                try self.ohlc_subscriptions.put(m.ticker.Owned.str, message.sender.?);
            },
        }
    }

    fn readMessage(context: *anyopaque, message: anyerror!?BrokerPayload) !void {
        const self = unsafeAnyOpaqueCast(Self, context);

        if (try message) |m| {
            switch (m) {
                .orderbook_update => |update| {
                    if (self.orderbook_subscriptions.get(update.symbol.Owned.str)) |subscriber| {
                        try subscriber.send(self.ctx.actor, OrderbookActorMessage{
                            .update = update.*,
                        });
                    }
                },
                .ohlc_update => |update| {
                    if (self.ohlc_subscriptions.get(update.symbol.Owned.str)) |subscriber| {
                        try subscriber.send(self.ctx.actor, OHLCActorMessage{
                            .update = update.*,
                        });
                    }
                },
            }
        }
    }
};
