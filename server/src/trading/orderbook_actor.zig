const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const shared_models = @import("shared_models");
const actor_message = @import("../actor_message/actor_message.pb.zig");
const orderbook_proto = @import("../actor_message/orderbook.pb.zig");

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerActorMessage = actor_message.BrokerActor.message_union;
const Envelope = backstage.Envelope;
const OrderbookUpdate = orderbook_proto.OrderbookUpdate;
const OrderbookLevel = orderbook_proto.OrderbookLevel;
const ConnectionMessage = conn_actr.ConnectionMessage;
const Orderbook = shared_models.Orderbook;
const ManagedString = shared_models.ManagedString;
const OrderbookActorMessage = actor_message.OrderbookActor.message_union;

pub const OrderbookActor = struct {
    arena_state: std.heap.ArenaAllocator,
    ctx: *Context,
    broker_actor: ?*ActorInterface = null,
    orderbook: ?Orderbook = null,
    subscriptions: std.ArrayList(*ActorInterface),
    notify_subscribers_completion: xev.Completion = undefined,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();

        self.* = .{
            .arena_state = arena_state,
            .ctx = ctx,
            .subscriptions = std.ArrayList(*ActorInterface).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        self.orderbook.?.deinit();
        try self.ctx.deinit();
        self.arena_state.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(OrderbookActorMessage)) !void {
        switch (message.payload) {
            .init => |_| {
                const broker_actor = try self.ctx.spawnActor(BrokerActor, BrokerActorMessage, .{
                    .id = "kraken_broker_actor",
                });

                try broker_actor.send(self.ctx.actor, BrokerActorMessage{ .init = .{ .broker = .KRAKEN } });
                self.broker_actor = broker_actor;
            },
            .start => |m| {
                const bids = std.ArrayList(shared_models.Level).init(self.arena_state.allocator());
                const asks = std.ArrayList(shared_models.Level).init(self.arena_state.allocator());
                self.orderbook = Orderbook{
                    .bids = bids,
                    .asks = asks,
                    .max_depth = 10,
                    .exchange = ManagedString.static("kraken"),
                    .ticker = m.ticker,
                };
                errdefer bids.deinit();
                errdefer asks.deinit();

                try self.broker_actor.?.send(self.ctx.actor, BrokerActorMessage{ .orderbook_subscribe = .{ .ticker = m.ticker } });
                try self.ctx.runContinuously(
                    Self,
                    notify_subscribers,
                    &self.notify_subscribers_completion,
                    self,
                    5,
                );
            },
            .update => |m| {
                try processLevelUpdates(&self.orderbook.?, m.bids, m.asks);
                m.deinit();
            },
            .subscribe => |_| {
                std.log.info("subscribing to orderbook: {s}", .{self.orderbook.?.ticker.Owned.str});
                try self.subscriptions.append(message.sender.?);
            },
            .unsubscribe => |_| {
                std.log.info("unsubscribing from orderbook: {s}", .{self.orderbook.?.ticker.Owned.str});
                for (self.subscriptions.items, 0..) |actor, i| {
                    if (actor == message.sender.?) {
                        _ = self.subscriptions.orderedRemove(i);
                        break;
                    }
                }
            },
        }
    }
    fn notify_subscribers(self: *Self) !void {
        for (self.subscriptions.items) |actor| {
            try actor.send(
                self.ctx.actor,
                ConnectionMessage{ .orderbook_update = &self.orderbook.? },
            );
        }
    }
};

fn processLevelUpdates(orderbook: *Orderbook, bids: std.ArrayList(OrderbookLevel), asks: std.ArrayList(OrderbookLevel)) !void {
    for (bids.items) |bid| {
        try updateOrderbook(orderbook, bid.price, bid.size, true);
    }

    for (asks.items) |ask| {
        try updateOrderbook(orderbook, ask.price, ask.size, false);
    }
}
fn updateOrderbook(orderbook: *Orderbook, price: f64, qty: f64, is_bid: bool) !void {
    var levels = if (is_bid) &orderbook.bids else &orderbook.asks;
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

    if (levels.items.len > orderbook.max_depth) {
        try levels.resize(orderbook.max_depth);
    }
}
fn priceDescending(_: void, a: shared_models.Level, b: shared_models.Level) bool {
    return a.price > b.price;
}

fn priceAscending(_: void, a: shared_models.Level, b: shared_models.Level) bool {
    return a.price < b.price;
}
