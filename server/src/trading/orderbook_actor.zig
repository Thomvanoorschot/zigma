const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const shared_models = @import("shared_models");

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerActorMessage = shared_models.BrokerActor;
const Envelope = backstage.Envelope;
const OrderbookUpdate = shared_models.OrderbookUpdate;
const OrderbookLevel = shared_models.OrderbookLevel;
const ConnectionActorMessage = shared_models.ConnectionActor;
const Orderbook = shared_models.Orderbook;
const ManagedString = shared_models.ManagedString;
const OrderbookActorMessage = shared_models.OrderbookActor;

pub const OrderbookActor = struct {
    allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    ctx: *Context,
    broker_actor: ?*ActorInterface = null,
    orderbook: ?Orderbook = null,
    subscriptions: std.ArrayList([]const u8),
    notify_subscribers_completion: xev.Completion = undefined,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();

        self.* = .{
            .allocator = allocator,
            .arena_state = arena_state,
            .ctx = ctx,
            .subscriptions = std.ArrayList([]const u8).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        for (self.subscriptions.items) |actor_id| {
            self.allocator.free(actor_id);
        }

        self.subscriptions.deinit();
        self.arena_state.deinit();
    }

    pub fn receive(self: *Self, message: Envelope) !void {
        const orderbook_msg: OrderbookActorMessage = try OrderbookActorMessage.decode(message.payload, self.allocator);

        if (orderbook_msg.message == null) {
            return error.InvalidMessage;
        }
        switch (orderbook_msg.message.?) {
            .init => |_| {
                const broker_actor = try self.ctx.spawnActor(BrokerActor, .{
                    .id = "kraken_broker_actor",
                });
                const init_msg = BrokerActorMessage{ .message = .{ .init = .{ .broker = .KRAKEN } } };
                const init_msg_bytes = try init_msg.encode(self.allocator);
                defer self.allocator.free(init_msg_bytes);
                try broker_actor.send(self.ctx.actor, init_msg_bytes);
                self.broker_actor = broker_actor;
            },
            .start => |m| {
                const bids = std.ArrayList(shared_models.OrderbookLevel).init(self.arena_state.allocator());
                const asks = std.ArrayList(shared_models.OrderbookLevel).init(self.arena_state.allocator());
                self.orderbook = Orderbook{
                    .bids = bids,
                    .asks = asks,
                    .max_depth = 10,
                    .exchange = ManagedString.static("kraken"),
                    .ticker = m.ticker,
                };
                errdefer bids.deinit();
                errdefer asks.deinit();

                const orderbook_subscribe_msg = BrokerActorMessage{ .message = .{ .orderbook_subscribe = .{ .ticker = m.ticker } } };
                const orderbook_subscribe_msg_bytes = try orderbook_subscribe_msg.encode(self.allocator);
                defer self.allocator.free(orderbook_subscribe_msg_bytes);
                try self.broker_actor.?.send(self.ctx.actor, orderbook_subscribe_msg_bytes);
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
                try self.subscriptions.append(try self.allocator.dupe(u8, message.senderID.?));
            },
            .unsubscribe => |_| {
                std.log.info("unsubscribing from orderbook: {s}", .{self.orderbook.?.ticker.Owned.str});
                for (self.subscriptions.items, 0..) |actor_id, i| {
                    if (std.mem.eql(u8, actor_id, message.senderID.?)) {
                        _ = self.subscriptions.orderedRemove(i);
                        self.allocator.free(actor_id);
                        break;
                    }
                }
            },
        }
    }
    fn notify_subscribers(self: *Self) !void {
        for (self.subscriptions.items) |actorID| {
            const orderbook_update_msg = ConnectionActorMessage{ .message = .{ .orderbook_update = self.orderbook.? } };
            const orderbook_update_msg_bytes = try orderbook_update_msg.encode(self.allocator);
            defer self.allocator.free(orderbook_update_msg_bytes);
            try self.ctx.send(actorID, orderbook_update_msg_bytes);
        }
    }
};

fn processLevelUpdates(orderbook: *Orderbook, bids: std.ArrayList(OrderbookLevel), asks: std.ArrayList(OrderbookLevel)) !void {
    for (bids.items) |bid| {
        try updateOrderbook(orderbook, bid.price, bid.qty, true);
    }

    for (asks.items) |ask| {
        try updateOrderbook(orderbook, ask.price, ask.qty, false);
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
                levels.items[i] = .{ .price = price, .qty = qty };
            }
            is_update = true;
        }
    }
    if (!is_update) {
        try levels.append(.{ .price = price, .qty = qty });
    }
    if (is_bid) {
        std.mem.sort(shared_models.OrderbookLevel, levels.items, {}, comptime priceDescending);
    } else {
        std.mem.sort(shared_models.OrderbookLevel, levels.items, {}, comptime priceAscending);
    }

    if (levels.items.len > orderbook.max_depth) {
        try levels.resize(orderbook.max_depth);
    }
}
fn priceDescending(_: void, a: shared_models.OrderbookLevel, b: shared_models.OrderbookLevel) bool {
    return a.price > b.price;
}

fn priceAscending(_: void, a: shared_models.OrderbookLevel, b: shared_models.OrderbookLevel) bool {
    return a.price < b.price;
}

// test "can receive orderbook updates" {
//     std.testing.log_level = .info;
//     var engine = try backstage.Engine.init(std.testing.allocator);

//     _ = try engine.spawnActor(OrderbookActor, .{
//         .id = "orderbook_actor",
//     });

//     const init_msg = OrderbookActorMessage{ .message = .{ .init = .{ .broker = .KRAKEN } } };
//     const init_msg_bytes = try init_msg.encode(std.testing.allocator);

//     try engine.send(null, "orderbook_actor", init_msg_bytes);

//     std.testing.allocator.free(init_msg_bytes);

//     const start_time = std.time.milliTimestamp();
//     const duration_ms = 2000;

//     while (std.time.milliTimestamp() - start_time < duration_ms) {
//         try engine.loop.run(.once);
//     }
//     engine.deinit();

//     std.log.info("test completed", .{});
// }

test "updateOrderbook functionality" {
    const bids = std.ArrayList(OrderbookLevel).init(std.testing.allocator);
    const asks = std.ArrayList(OrderbookLevel).init(std.testing.allocator);

    var orderbook = Orderbook{
        .bids = bids,
        .asks = asks,
        .max_depth = 10,
        .exchange = ManagedString.static("test"),
        .ticker = ManagedString.static("BTC-USD"),
    };
    defer orderbook.deinit();

    var i: f64 = 0;
    while (i < 40) : (i += 1) {
        const price = 50000.0 - (i * 10.0);
        const qty = 1.0 + (i * 0.1);
        try updateOrderbook(&orderbook, price, qty, true);
    }

    i = 0;
    while (i < 40) : (i += 1) {
        const price = 50100.0 + (i * 10.0);
        const qty = 0.5 + (i * 0.05);
        try updateOrderbook(&orderbook, price, qty, false);
    }

    try std.testing.expect(orderbook.bids.items.len == 10);
    try std.testing.expect(orderbook.asks.items.len == 10);

    try std.testing.expectApproxEqAbs(orderbook.bids.items[0].price, 50000.0, 1e-9);
    try std.testing.expectApproxEqAbs(orderbook.bids.items[1].price, 49990.0, 1e-9);
    try std.testing.expectApproxEqAbs(orderbook.bids.items[2].price, 49980.0, 1e-9);
    try std.testing.expectApproxEqAbs(orderbook.bids.items[9].price, 49910.0, 1e-9);

    try std.testing.expectApproxEqAbs(orderbook.asks.items[0].price, 50100.0, 1e-9);
    try std.testing.expectApproxEqAbs(orderbook.asks.items[1].price, 50110.0, 1e-9);
    try std.testing.expectApproxEqAbs(orderbook.asks.items[2].price, 50120.0, 1e-9);
    try std.testing.expectApproxEqAbs(orderbook.asks.items[9].price, 50190.0, 1e-9);

    try updateOrderbook(&orderbook, 50000.0, 0.0, true);
    try std.testing.expect(orderbook.bids.items.len == 9);

    try std.testing.expectApproxEqAbs(orderbook.bids.items[0].price, 49990.0, 1e-9);
}
