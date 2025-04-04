const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const orderbook = @import("orderbook.zig");
const conn_actr = @import("../http/connection_actor.zig");

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerMessage = brkr_actr.BrokerMessage;
const Envelope = backstage.Envelope;
const OrderbookUpdate = brkr_impl.OrderbookUpdate;
const Orderbook = orderbook.OrderBook;
const ConnectionMessage = conn_actr.ConnectionMessage;
const updateOrderbook = orderbook.updateOrderbook;

pub const OrderbookMessage = union(enum) {
    init: OrderbookInitRequest,
    start: OrderbookStartRequest,
    orderbook_update: OrderbookUpdate,
    subscribe: OrderbookSubscribeRequest,
};

pub const OrderbookInitRequest = struct {
    broker: BrokerType,
};
pub const OrderbookStartRequest = struct {
    ticker: []const u8,
};
pub const OrderbookSubscribeRequest = struct {};
pub const OrderbookResponse = struct {
    last_timestamp: []const u8,
};

pub const OrderbookActor = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    ticker: []const u8 = "",
    ctx: *Context,
    broker_actor: ?*ActorInterface = null,
    orderbook: ?Orderbook = null,
    subscriptions: std.ArrayList(*ActorInterface),
    notify_subscribers_completion: xev.Completion = undefined,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        self.* = .{
            .allocator = allocator,
            .arena = arena,
            .ctx = ctx,
            .subscriptions = std.ArrayList(*ActorInterface).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(OrderbookMessage)) !void {
        switch (message.payload) {
            .init => |_| {
                const broker_actor = try self.ctx.spawnActor(BrokerActor, BrokerMessage, .{
                    .id = "broker_actor",
                });

                try broker_actor.send(self.ctx.actor, BrokerMessage{ .init = .{ .broker = .kraken } });
                self.broker_actor = broker_actor;
            },
            .start => |m| {
                self.ticker = m.ticker;
                self.orderbook = try Orderbook.init(self.allocator, "kraken", self.ticker, 10);
                try self.broker_actor.?.send(self.ctx.actor, BrokerMessage{ .subscribe = .{ .ticker = m.ticker } });
                try self.ctx.runContinuously(
                    Self,
                    notify_subscribers,
                    &self.notify_subscribers_completion,
                    self,
                    1000,
                );
            },
            .orderbook_update => |m| {
                _ = try updateOrderbook(&self.orderbook.?, m);
                // self.orderbook.?.display();
                // for (self.subscriptions.items) |actor| {
                //     try actor.send(self.ctx.actor, ConnectionMessage{ .orderbook_update = &self.orderbook.? });
                // }
                m.deinit();
            },
            .subscribe => |_| {
                try self.subscriptions.append(message.sender.?);
            },
        }
    }
    fn notify_subscribers(self: *Self) !void {
        for (self.subscriptions.items) |actor| {
            try actor.send(self.ctx.actor, ConnectionMessage{ .orderbook_update = &self.orderbook.? });
        }
    }
};
