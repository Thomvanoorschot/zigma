const std = @import("std");
const alphazig = @import("alphazig");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const concurrency = alphazig.concurrency;
const ActorInterface = alphazig.ActorInterface;
const Coroutine = concurrency.Coroutine;
const Allocator = std.mem.Allocator;
const Context = alphazig.Context;
const Request = alphazig.Request;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerMessage = brkr_actr.BrokerMessage;

pub const OrderbookMessage = union(enum) {
    init: OrderbookInitRequest,
    start: OrderbookStartRequest,
    request: OrderbookRequest,
};

pub const OrderbookInitRequest = struct {
    broker: BrokerType,
};
pub const OrderbookStartRequest = struct {
    ticker: []const u8,
};
pub const OrderbookRequest = struct {};
pub const OrderbookResponse = struct {
    last_timestamp: []const u8,
};

pub const OrderbookActor = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    ticker: []const u8 = "",
    ctx: *Context,
    broker_actor: ?*ActorInterface = null,

    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        self.* = .{
            .allocator = allocator,
            .arena = arena,
            .ctx = ctx,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn receive(self: *Self, message: *const OrderbookMessage) !void {
        switch (message.*) {
            .init => |_| {
                const broker_actor = try self.ctx.spawnActor(BrokerActor, BrokerMessage, .{
                    .id = "broker_actor",
                });

                try broker_actor.send(BrokerMessage{ .init = .{ .broker = .kraken } });
                self.broker_actor = broker_actor;
            },
            .start => |m| {
                self.ticker = m.ticker;
                try self.broker_actor.?.send(BrokerMessage{ .subscribe = .{ .ticker = m.ticker } });
            },
            .request => |_| {
                while (true) {
                    try self.broker_actor.?.send(BrokerMessage{ .request = .{} });
                    self.ctx.yield();
                }
            },
        }
    }
};
