const std = @import("std");
const alphazig = @import("alphazig");
const concurrency = alphazig.concurrency;
const brkr_actr = @import("trading/broker_actor.zig");
const brkr_impl = @import("trading/broker_impl.zig");
const ob_actr = @import("trading/orderbook_actor.zig");

const BrokerActor = brkr_actr.BrokerActor;
const BrokerType = brkr_impl.BrokerType;
const EmptyArgs = concurrency.EmptyArgs;
const Engine = alphazig.Engine;
const OrderbookActor = ob_actr.OrderbookActor;
const OrderbookMessage = ob_actr.OrderbookMessage;
pub fn main() !void {
    concurrency.run(mainRoutine);
}
pub fn mainRoutine(_: EmptyArgs) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const scheduler = alphazig.concurrency.Scheduler.init(null);

    var engine = Engine.init(allocator);
    defer engine.deinit();

    const orderbook_actor = try engine.spawnActor(OrderbookActor, OrderbookMessage, .{
        .id = "orderbook_actor",
    });
    _ = orderbook_actor;

    try engine.send("orderbook_actor", OrderbookMessage{ .init = .{ .broker = .kraken } });
    try engine.send("orderbook_actor", OrderbookMessage{ .start = .{ .ticker = "BTC/USD" } });
    std.debug.print("Hello, world!\n", .{});
    scheduler.suspend_routine();
}
