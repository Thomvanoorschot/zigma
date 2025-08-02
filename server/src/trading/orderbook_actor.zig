const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const BrokerActorProxy = @import("../generated/broker_actor_proxy.gen.zig").BrokerActorProxy;
const OrderbookActorProxy = @import("../generated/orderbook_actor_proxy.gen.zig").OrderbookActorProxy;
const OrderbookUpdate = @import("types/orderbook_update.zig").OrderbookUpdate;
const Orderbook = @import("types/orderbook.zig").Orderbook;
const OrderbookLevel = @import("types/orderbook_level.zig").OrderbookLevel;
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const Envelope = backstage.Envelope;
const newSubscriber = backstage.newSubscriber;

// @generate-proxy
pub const OrderbookActor = struct {
    allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    ctx: *Context,
    orderbook: ?Orderbook = null,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();

        self.* = .{
            .allocator = allocator,
            .arena_state = arena_state,
            .ctx = ctx,
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        self.arena_state.deinit();
        if (self.orderbook != null) {
            self.orderbook.?.deinit();
        }
    }

    pub fn start(self: *Self, ticker: []const u8) !void {
        const bids = std.ArrayList(OrderbookLevel).init(self.arena_state.allocator());
        const asks = std.ArrayList(OrderbookLevel).init(self.arena_state.allocator());
        self.orderbook = Orderbook{
            .bids = bids,
            .asks = asks,
            .max_depth = 10,
            .exchange = "kraken",
            .ticker = ticker,
        };
        errdefer bids.deinit();
        errdefer asks.deinit();

        const broker_actor = try self.ctx.getActor(BrokerActorProxy, "kraken_broker_actor");
        try broker_actor.start(ticker, .ORDERBOOK);

        var topic_buf: [40]u8 = undefined;
        const stream_id = try std.fmt.bufPrintZ(&topic_buf, "orderbook_updates_{s}", .{self.orderbook.?.ticker});
        const stream = try self.ctx.getStream(OrderbookUpdate, stream_id);
        try stream.subscribe(newSubscriber(self.ctx.actor_id, OrderbookActorProxy.Method.update));
    }

    pub fn update(self: *Self, u: OrderbookUpdate) !void {
        try self.orderbook.?.processLevelUpdates(u.bids, u.asks);
        var stream_buf: [40]u8 = undefined;
        const stream_id = try std.fmt.bufPrintZ(&stream_buf, "{s}_orderbook_actor", .{self.orderbook.?.ticker});
        const stream = try self.ctx.getStream(Orderbook, stream_id);
        try stream.next(self.orderbook.?);
    }
};

// test "can receive orderbook updates" {
//     std.testing.log_level = .info;
//     var engine = try backstage.Engine.init(std.testing.allocator);

//     const orderbook_actor = try engine.spawnActor(OrderbookActor, .{
//         .id = "orderbook_actor",
//     });

//     orderbook_actor.orderbook = Orderbook{
//         .bids = std.ArrayList(OrderbookLevel).init(std.testing.allocator),
//         .asks = std.ArrayList(OrderbookLevel).init(std.testing.allocator),
//         .max_depth = 10,
//         .exchange = ManagedString.static("kraken"),
//         .ticker = ManagedString.static("BTC-USD"),
//     };

//     try engine.send("orderbook_actor", OrderbookActorMessage{ .message = .{
//         .update = .{
//             .bids = std.ArrayList(OrderbookLevel).init(std.testing.allocator),
//             .asks = std.ArrayList(OrderbookLevel).init(std.testing.allocator),
//             .ticker = ManagedString.static("BTC-USD"),
//             .checksum = 0,
//             .timestamp = null,
//         },
//     } });

//     const start_time = std.time.milliTimestamp();
//     const duration_ms = 2000;
//     while (std.time.milliTimestamp() - start_time < duration_ms) {
//         try engine.loop.run(.once);
//     }

//     try orderbook_actor.deinit();
//     engine.deinit();
// }

// test "updateOrderbook functionality" {
//     const bids = std.ArrayList(OrderbookLevel).init(std.testing.allocator);
//     const asks = std.ArrayList(OrderbookLevel).init(std.testing.allocator);

//     var orderbook = Orderbook{
//         .bids = bids,
//         .asks = asks,
//         .max_depth = 10,
//         .exchange = ManagedString.static("test"),
//         .ticker = ManagedString.static("BTC-USD"),
//     };
//     defer orderbook.deinit();

//     var i: f64 = 0;
//     while (i < 40) : (i += 1) {
//         const price = 50000.0 - (i * 10.0);
//         const qty = 1.0 + (i * 0.1);
//         try updateOrderbook(&orderbook, price, qty, true);
//     }

//     i = 0;
//     while (i < 40) : (i += 1) {
//         const price = 50100.0 + (i * 10.0);
//         const qty = 0.5 + (i * 0.05);
//         try updateOrderbook(&orderbook, price, qty, false);
//     }

//     try std.testing.expect(orderbook.bids.items.len == 10);
//     try std.testing.expect(orderbook.asks.items.len == 10);

//     try std.testing.expectApproxEqAbs(orderbook.bids.items[0].price, 50000.0, 1e-9);
//     try std.testing.expectApproxEqAbs(orderbook.bids.items[1].price, 49990.0, 1e-9);
//     try std.testing.expectApproxEqAbs(orderbook.bids.items[2].price, 49980.0, 1e-9);
//     try std.testing.expectApproxEqAbs(orderbook.bids.items[9].price, 49910.0, 1e-9);

//     try std.testing.expectApproxEqAbs(orderbook.asks.items[0].price, 50100.0, 1e-9);
//     try std.testing.expectApproxEqAbs(orderbook.asks.items[1].price, 50110.0, 1e-9);
//     try std.testing.expectApproxEqAbs(orderbook.asks.items[2].price, 50120.0, 1e-9);
//     try std.testing.expectApproxEqAbs(orderbook.asks.items[9].price, 50190.0, 1e-9);

//     try updateOrderbook(&orderbook, 50000.0, 0.0, true);
//     try std.testing.expect(orderbook.bids.items.len == 9);

//     try std.testing.expectApproxEqAbs(orderbook.bids.items[0].price, 49990.0, 1e-9);
// }
