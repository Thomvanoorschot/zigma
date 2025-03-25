const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const orderbook_actor = @import("orderbook_actor.zig");

const xev = backstage.xev;
const Context = backstage.Context;
const BrokerImpl = brkr_impl.BrokerImpl;
const BrokerType = brkr_impl.BrokerType;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const OrderbookMessage = orderbook_actor.OrderbookMessage;

pub const BrokerMessage = union(enum) {
    init: BrokerInitRequest,
    subscribe: BrokerSubscribeRequest,
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
    subscriptions: std.ArrayList(*ActorInterface),
    completion: xev.Completion = undefined,

    const Self = @This();
    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .subscriptions = std.ArrayList(*ActorInterface).init(allocator),
        };

        return self;
    }

    pub fn receive(self: *Self, message: *const Envelope(BrokerMessage)) !void {
        switch (message.payload) {
            .init => |m| {
                self.broker = try BrokerImpl.init(self.allocator, m.broker);
                try self.ctx.runContinuously(Self, readMessages, &self.completion, @ptrCast(self));
            },
            .subscribe => |m| {
                // TODO Split this up into seperate messages?
                try self.broker.?.subscribeToOrderbook(m.ticker);
                try self.subscriptions.append(message.sender.?);
            },
        }
    }
    fn readMessages(self: *Self) !void {
        const message = try self.broker.?.readMessage();
        if (message) |m| {
            switch (m) {
                .orderbook_update => |update| {
                    for (self.subscriptions.items) |actor| {
                        try actor.send(self.ctx.actor, OrderbookMessage{ .orderbook_update = update });
                    }
                },
            }
        }
    }
};
