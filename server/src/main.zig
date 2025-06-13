const std = @import("std");
const backstage = @import("backstage");
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");
const ohlc_actr = @import("trading/ohlc_actor.zig");
const server_actr = @import("http/server_actor.zig");
const shared_models = @import("shared_models");
const broker_message = @import("trading/broker_actor.zig");
const type_utils = @import("utils/type_utils.zig");

const ManagedString = shared_models.ManagedString;
const xev = backstage.xev;
const Timer = xev.Timer;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookActorMessage = shared_models.OrderbookActor;
const ServerActor = server_actr.ServerActor;
const ServerActorMessage = shared_models.ServerActor;
const OHLCActor = ohlc_actr.OHLCActor;
const OHLCActorMessage = shared_models.OHLCActor;
const BrokerActorMessage = shared_models.BrokerActor;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.detectLeaks();
        if (leaked) {
            std.log.err("Main application leaked memory!", .{});
        }
    }
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    const broker_actor = try engine.spawnActor(BrokerActor, .{
        .id = "kraken_broker_actor",
    });
    try engine.send(
        null,
        broker_actor.ctx.actor_id,
        .send,
        BrokerActorMessage{ .message = .{ .init = .{ .broker = .KRAKEN } } },
    );

    const server_actor = try engine.spawnActor(ServerActor, .{
        .id = "server_actor",
    });

    try engine.send(null, server_actor.ctx.actor_id, .send, ServerActorMessage{
        .message = .{ .init = .{
            .host = ManagedString.static("0.0.0.0"),
            .port = 8081,
            .max_connections = 1024,
        } },
    });

    try engine.send(
        null,
        server_actor.ctx.actor_id,
        .send,
        ServerActorMessage{ .message = .{ .accept = .{} } },
    );

    const tickers = [_][]const u8{ "ETH/USD", "BTC/USD", "XRP/USD", "DOGE/USD", "SUI/USD", "USDC/USD", "SOL/USD", "PEPE/USD", "ADA/USD", "WIF/USD", "EUR/USD", "FARTCOIN/USD", "AVAX/USD", "LTC/USD", "XLM/USD", "TRUMP/USD" };
    for (tickers) |ticker| {
        // Orderbook
        const orderbook_actor = try engine.spawnActor(OrderbookActor, .{
            .id = try std.fmt.allocPrintZ(allocator, "{s}_orderbook_actor", .{ticker}),
        });
        try engine.send(null, orderbook_actor.ctx.actor_id, .send, OrderbookActorMessage{
            .message = .{ .start = .{ .ticker = try ManagedString.copy(ticker, allocator) } },
        });

        // OHLC
        const ohlc_actor = try engine.spawnActor(OHLCActor, .{
            .id = try std.fmt.allocPrintZ(allocator, "{s}_ohlc_actor", .{ticker}),
        });
        try engine.send(null, ohlc_actor.ctx.actor_id, .send, OHLCActorMessage{
            .message = .{ .start = .{ .ticker = try ManagedString.copy(ticker, allocator) } },
        });
    }

    try engine.run();
}

test {
    _ = @import("trading/orderbook_actor.zig");
}
