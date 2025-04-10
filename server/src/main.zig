const std = @import("std");
const backstage = @import("backstage");
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");
const ohlc_actr = @import("trading/ohlc_actor.zig");
const server_actr = @import("http/server_actor.zig");

const xev = backstage.xev;
const Timer = xev.Timer;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookMessage = ob_actr.OrderbookMessage;
const ServerActor = server_actr.ServerActor;
const ServerMessage = server_actr.ServerMessage;
const OHLCActor = ohlc_actr.OHLCActor;
const OHLCMessage = ohlc_actr.OHLCMessage;
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

    const server_actor = try engine.spawnActor(ServerActor, ServerMessage, .{
        .id = "server_actor",
    });
    try server_actor.send(null, ServerMessage{ .init = .{
        .address = try std.net.Address.parseIp4("127.0.0.1", 8081),
        .max_connections = 1024,
    } });
    try server_actor.send(null, ServerMessage{ .listen = .{} });

    // const orderbook_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
    //     .id = "orderbook_actor",
    // });
    // try orderbook_actor.send(null, OrderbookMessage{ .init = .{ .broker = .kraken } });
    // try orderbook_actor.send(null, OrderbookMessage{ .start = .{ .ticker = "BTC/USD" } });

    const ohlc_actor = try engine.spawnActor(OHLCActor, OHLCMessage, .{
        .id = "ohlc_actor",
    });
    try ohlc_actor.send(null, OHLCMessage{ .init = .{ .broker = .kraken } });
    try ohlc_actor.send(null, OHLCMessage{ .start = .{ .ticker = "BTC/USD" } });

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
        const s: *Engine = @as(*Engine, @ptrCast(@alignCast(ud.?)));
        std.debug.print("Timer fired: Signaling engine loop to stop.\n", .{});
        s.deinit();

        return .disarm;
    }
}.inner;
