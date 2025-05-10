const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const shared_models = @import("shared_models");
const obu = @import("orderbook_update.zig");

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerMessage = brkr_actr.BrokerMessage;
const Envelope = backstage.Envelope;
const OrderbookUpdate = obu.OrderbookUpdate;
const ConnectionMessage = conn_actr.ConnectionMessage;
const Orderbook = shared_models.OrderBook;

pub const OrderbookMessage = union(enum) {
    init: OrderbookInitRequest,
    start: OrderbookStartRequest,
    orderbook_update: OrderbookUpdate,
    subscribe: OrderbookSubscribeRequest,
    unsubscribe: OrderbookSubscribeRequest,
};

pub const OrderbookInitRequest = struct {
    broker: BrokerType,
};
pub const OrderbookStartRequest = struct {
    ticker: []const u8,
};
pub const OrderbookSubscribeRequest = struct {};
pub const OrderbookUnsubscribeRequest = struct {};

pub const OrderbookActor = struct {
    allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    ticker: []const u8 = "",
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
            .allocator = allocator,
            .arena_state = arena_state,
            .ctx = ctx,
            .subscriptions = std.ArrayList(*ActorInterface).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        try self.ctx.deinit();
        self.arena_state.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(OrderbookMessage)) !void {
        switch (message.payload) {
            .init => |_| {
                const broker_actor = try self.ctx.spawnActor(BrokerActor, BrokerMessage, .{
                    .id = "kraken_broker_actor",
                });

                try broker_actor.send(self.ctx.actor, BrokerMessage{ .init = .{ .broker = .kraken } });
                self.broker_actor = broker_actor;
            },
            .start => |m| {
                self.ticker = m.ticker;
                self.orderbook = try Orderbook.init(self.allocator, "kraken", self.ticker, 10);
                try self.broker_actor.?.send(self.ctx.actor, BrokerMessage{ .orderbook_subscribe = .{ .ticker = m.ticker } });
                try self.ctx.runContinuously(
                    Self,
                    notify_subscribers,
                    &self.notify_subscribers_completion,
                    self,
                    5,
                );
            },
            .orderbook_update => |m| {
                var ob_update: OrderbookUpdate = m;

                // TODO Probably move this to some other better place
                const asks = try self.arena_state.allocator().alloc(shared_models.PriceLevel, ob_update.data.asks.len);
                for (ob_update.data.asks, 0..) |ask, i| {
                    asks[i] = .{ .price = ask.price, .qty = ask.qty };
                }
                const bids = try ob_update.arena_state.allocator().alloc(shared_models.PriceLevel, ob_update.data.bids.len);
                for (ob_update.data.bids, 0..) |bid, i| {
                    bids[i] = .{ .price = bid.price, .qty = bid.qty };
                }
                try self.orderbook.?.processUpdates(bids, asks);
                ob_update.deinit();
            },
            .subscribe => |_| {
                try self.subscriptions.append(message.sender.?);
            },
            .unsubscribe => |_| {
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
