const std = @import("std");
const backstage = @import("backstage");
const concurrency = backstage.concurrency;
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");
const httpz = @import("httpz");
const server_actr = @import("http/server_actor.zig");
const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const EmptyArgs = concurrency.EmptyArgs;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookMessage = ob_actr.OrderbookMessage;
const ServerActor = server_actr.ServerActor;
const ServerMessage = server_actr.ServerMessage;
pub fn main() !void {
    concurrency.run(mainRoutine);
}

pub fn mainRoutine(_: EmptyArgs) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const scheduler = backstage.concurrency.Scheduler.init(null);

    var engine = Engine.init(allocator);
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
    scheduler.suspend_routine();
}
