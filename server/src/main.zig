const std = @import("std");
const backstage = @import("backstage");
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");
const ohlc_actr = @import("trading/ohlc_actor.zig");
const server_actr = @import("http/server_actor.zig");
const shared_models = @import("shared_models");
const unsafeAnyOpaqueCast = @import("utils/type_utils.zig").unsafeAnyOpaqueCast;

const ManagedString = shared_models.ManagedString;
const xev = backstage.xev;
const Timer = xev.Timer;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookActorMessage = shared_models.OrderbookActor.message_union;
const ServerActor = server_actr.ServerActor;
const ServerActorMessage = shared_models.ServerActor;
const OHLCActor = ohlc_actr.OHLCActor;
const OHLCActorMessage = ohlc_actr.OHLCActor.message_union;
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

    const server_actor = try engine.spawnActor(ServerActor, .{
        .id = "server_actor",
    });
    const init_server_msg = ServerActorMessage{
        .message = .{ .init = .{
            .host = ManagedString.static("127.0.0.1"),
            .port = 8081,
            .max_connections = 1024,
        } },
    };
    const init_server_msg_bytes = try init_server_msg.encode(allocator);
    try server_actor.send(null, init_server_msg_bytes);

    const accept_server_msg = ServerActorMessage{
        .message = .{ .accept = .{} },
    };
    const accept_server_msg_bytes = try accept_server_msg.encode(allocator);
    try server_actor.send(null, accept_server_msg_bytes);

    // const tickers = [_][]const u8{ "ETH/USD", "BTC/USD", "XRP/USD", "DOGE/USD", "SUI/USD", "USDC/USD", "SOL/USD", "PEPE/USD", "ADA/USD", "WIF/USD", "EUR/USD", "FARTCOIN/USD", "AVAX/USD", "LTC/USD", "XLM/USD", "TRUMP/USD" };
    // for (tickers) |ticker| {
    //     const orderbook_actor = try engine.spawnActor(OrderbookActor, .{
    //         .id = try std.fmt.allocPrintZ(allocator, "{s}_orderbook_actor", .{ticker}),
    //     });
    //     try orderbook_actor.send(null, OrderbookActorMessage{ .init = .{ .broker = .KRAKEN } });
    //     try orderbook_actor.send(null, OrderbookActorMessage{ .start = .{ .ticker = try ManagedString.copy(ticker, allocator) } });
    // }

    // const ohlc_actor = try engine.spawnActor(OHLCActor, OHLCMessage, .{
    //     .id = "ohlc_actor",
    // });
    // try ohlc_actor.send(null, OHLCMessage{ .init = .{ .broker = .kraken } });
    // try ohlc_actor.send(null, OHLCMessage{ .start = .{ .ticker = "BTC/USD" } });

    // const test_second_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
    //     .id = "test_second_actor",
    // });
    // try test_second_actor.send(null, OrderbookMessage{ .init = .{ .broker = .kraken } });
    // try test_second_actor.send(null, OrderbookMessage{ .start = .{ .ticker = "ETH/USD" } });

    // const test_third_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
    //     .id = "test_third_actor",
    // });
    // try test_third_actor.send(null, OrderbookMessage{ .init = .{ .broker = .kraken } });
    // try test_third_actor.send(null, OrderbookMessage{ .start = .{ .ticker = "OMNI/USD" } });

    // Stopping doesn't quite work yet
    // var cc = xev.Completion{};
    // engine.loop.timer(&cc, 2000, @ptrCast(&engine), listenForMessagesFn);
    try engine.run();
}
const listenForMessagesFn = struct {
    fn inner(
        ud: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.Result,
    ) xev.CallbackAction {
        const s = unsafeAnyOpaqueCast(Engine, ud.?);
        std.debug.print("Timer fired: Signaling engine loop to stop.\n", .{});
        s.deinit();

        return .disarm;
    }
}.inner;
