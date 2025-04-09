const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const shared_models = @import("shared_models");
const ohclu = @import("ohcl_update.zig");

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerMessage = brkr_actr.BrokerMessage;
const Envelope = backstage.Envelope;
const ConnectionMessage = conn_actr.ConnectionMessage;
const OHLCUpdate = ohclu.OHLCUpdate;
pub const OHLCMessage = union(enum) {
    init: OHLCInitRequest,
    start: OHLCStartRequest,
    ohlc_update: OHLCUpdate,
    subscribe: OHLCSubscribeRequest,
};

pub const OHLCInitRequest = struct {
    broker: BrokerType,
};
pub const OHLCStartRequest = struct {
    ticker: []const u8,
};
pub const OHLCSubscribeRequest = struct {};
pub const OHLCResponse = struct {
    last_timestamp: []const u8,
};

pub const OHLCActor = struct {
    allocator: Allocator,
    arena: std.heap.ArenaAllocator,
    ticker: []const u8 = "",
    ctx: *Context,
    broker_actor: ?*ActorInterface = null,
    subscriptions: std.ArrayList(*ActorInterface),
    notify_subscribers_completion: xev.Completion = undefined,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        self.* = .{
            .allocator = allocator,
            .arena = arena,
            .ctx = ctx,
            .subscriptions = std.ArrayList(*ActorInterface).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(OHLCMessage)) !void {
        switch (message.payload) {
            .init => |_| {
                const broker_actor = try self.ctx.spawnActor(BrokerActor, BrokerMessage, .{
                    .id = "kraken_broker_actor",
                });

                try broker_actor.send(self.ctx.actor, BrokerMessage{ .init = .{ .broker = .kraken } });
                self.broker_actor = broker_actor;
            },
            .start => |m| {
                self.ticker = m.ticker;
                try self.broker_actor.?.send(self.ctx.actor, BrokerMessage{ .ohlc_subscribe = .{ .ticker = m.ticker } });
                try self.ctx.runContinuously(
                    Self,
                    notify_subscribers,
                    &self.notify_subscribers_completion,
                    self,
                    20,
                );
            },
            .ohlc_update => |m| {
                std.debug.print("OHLC Update\n", .{});
                var ohlc_update: OHLCUpdate = m;
                ohlc_update.deinit();
            },
            .subscribe => |_| {
                try self.subscriptions.append(message.sender.?);
            },
        }
    }
    fn notify_subscribers(_: *Self) !void {
        // for (self.subscriptions.items) |actor| {
        //     try actor.send(self.ctx.actor, OHLCMessage{ .ohlc_update = &self.orderbook.? });
        // }
    }
};
