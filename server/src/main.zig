const std = @import("std");
const backstage = @import("backstage");
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");
const server_actr = @import("http/server_actor.zig");

const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookMessage = ob_actr.OrderbookMessage;
const ServerActor = server_actr.ServerActor;
const ServerMessage = server_actr.ServerMessage;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var engine = try Engine.init(allocator);
    defer engine.deinit();

    const server_actor = try engine.spawnActor(ServerActor, ServerMessage, .{
        .id = "server_actor",
    });
    try server_actor.send(null, ServerMessage{ .listen = .{} });

    const orderbook_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "orderbook_actor",
    });
    try orderbook_actor.send(null, OrderbookMessage{ .init = .{ .broker = .kraken } });
    try orderbook_actor.send(null, OrderbookMessage{ .start = .{ .ticker = "BTC/USD" } });

    const test_second_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "test_second_actor",
    });
    try test_second_actor.send(null, OrderbookMessage{ .init = .{ .broker = .kraken } });
    try test_second_actor.send(null, OrderbookMessage{ .start = .{ .ticker = "ETH/USD" } });

    const test_third_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "test_third_actor",
    });
    try test_third_actor.send(null, OrderbookMessage{ .init = .{ .broker = .kraken } });
    try test_third_actor.send(null, OrderbookMessage{ .start = .{ .ticker = "XRP/USD" } });

    try engine.run();
}
