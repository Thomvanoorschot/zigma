const std = @import("std");
const backstage = @import("backstage");
const concurrency = backstage.concurrency;
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");

const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const EmptyArgs = concurrency.EmptyArgs;
const Engine = backstage.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookMessage = ob_actr.OrderbookMessage;
pub fn main() !void {
    concurrency.run(mainRoutine);
}
pub fn mainRoutine(_: EmptyArgs) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const scheduler = backstage.concurrency.Scheduler.init(null);

    var engine = Engine.init(allocator);
    defer engine.deinit();

    const orderbook_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "orderbook_actor",
    });
    _ = orderbook_actor;
    try engine.send(null, "orderbook_actor", OrderbookMessage{ .init = .{ .broker = .kraken } });
    try engine.send(null, "orderbook_actor", OrderbookMessage{ .start = .{ .ticker = "BTC/USD" } });

    const test_second_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "test_second_actor",
    });
    _ = test_second_actor;
    try engine.send(null, "test_second_actor", OrderbookMessage{ .init = .{ .broker = .kraken } });
    try engine.send(null, "test_second_actor", OrderbookMessage{ .start = .{ .ticker = "ETH/USD" } });

    const test_third_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "test_third_actor",
    });
    _ = test_third_actor;
    try engine.send(null, "test_third_actor", OrderbookMessage{ .init = .{ .broker = .kraken } });
    try engine.send(null, "test_third_actor", OrderbookMessage{ .start = .{ .ticker = "XRP/USD" } });
    scheduler.suspend_routine();
}
