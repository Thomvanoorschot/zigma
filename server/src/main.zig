const std = @import("std");
const backstage = @import("backstage");
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");
const ohlc_actr = @import("trading/ohlc_actor.zig");
const server_actr = @import("http/server_actor.zig");
const broker_message = @import("trading/broker_actor.zig");
const type_utils = @import("utils/type_utils.zig");

const BrokerActorProxy = @import("generated/broker_actor_proxy.gen.zig").BrokerActorProxy;
// const ServerActorProxy = @import("generated/server_actor_proxy.gen.zig").ServerActorProxy;
const OrderbookActorProxy = @import("generated/orderbook_actor_proxy.gen.zig").OrderbookActorProxy;
const OHLCActorProxy = @import("generated/ohlc_actor_proxy.gen.zig").OHLCActorProxy;

const xev = backstage.xev;
const Timer = xev.Timer;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const ServerActor = server_actr.ServerActor;
const OHLCActor = ohlc_actr.OHLCActor;
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

    const broker_actor = try engine.getActor(BrokerActorProxy, "kraken_broker_actor");
    try broker_actor.setup(.KRAKEN);

    // const server_actor = try engine.getActor(ServerActorProxy, "server_actor");
    // try server_actor.setup(
    //     "0.0.0.0",
    //     8081,
    //     1024,
    // );
    // try server_actor.accept();

    const tickers = [_][]const u8{ "ETH/USD", "BTC/USD", "XRP/USD", "DOGE/USD", "SUI/USD", "USDC/USD", "SOL/USD", "PEPE/USD", "ADA/USD", "WIF/USD", "EUR/USD", "FARTCOIN/USD", "AVAX/USD", "LTC/USD", "XLM/USD", "TRUMP/USD" };
    for (tickers) |ticker| {
        // Orderbook
        const orderbook_actor = try engine.getActor(
            OrderbookActorProxy,
            try std.fmt.allocPrintZ(allocator, "{s}_orderbook_actor", .{ticker}),
        );
        try orderbook_actor.start(ticker);

        // OHLC
        const ohlc_actor = try engine.getActor(
            OHLCActorProxy,
            try std.fmt.allocPrintZ(allocator, "{s}_ohlc_actor", .{ticker}),
        );
        try ohlc_actor.start(ticker);
    }

    try engine.run();
}

test {
    _ = @import("trading/orderbook_actor.zig");
}
