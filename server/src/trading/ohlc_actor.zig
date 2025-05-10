const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const shared_models = @import("shared_models");
const ohlcu = @import("ohlc_update.zig");

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const BrokerMessage = brkr_actr.BrokerMessage;
const Envelope = backstage.Envelope;
const ConnectionMessage = conn_actr.ConnectionMessage;
const OHLCUpdate = ohlcu.OHLCUpdate;
const OHLC = shared_models.OHLC;
const OHLCList = shared_models.OHLCList;
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
    ohlc_list: OHLCList,
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
            .ohlc_list = OHLCList.init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        try self.ctx.deinit();
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
                var ohlc_update: OHLCUpdate = m;
                const ohlc = OHLC{
                    .symbol = ohlc_update.data.symbol,
                    .open = ohlc_update.data.open,
                    .high = ohlc_update.data.high,
                    .low = ohlc_update.data.low,
                    .close = ohlc_update.data.close,
                    .trades = ohlc_update.data.trades,
                    .volume = ohlc_update.data.volume,
                    .interval = ohlc_update.data.interval,
                    .timestamp = ohlc_update.data.timestamp,
                };
                if (self.ohlc_list.getLastOrNull()) |last| {
                    if (std.mem.eql(u8, last.timestamp, ohlc.timestamp)) {
                        // TODO: Probably more effecient to update the last item
                        _ = self.ohlc_list.pop();
                        try self.ohlc_list.append(ohlc);
                    } else {
                        try self.ohlc_list.append(ohlc);
                    }
                } else {
                    try self.ohlc_list.append(ohlc);
                }
                ohlc_update.deinit();
            },
            .subscribe => |_| {
                try self.subscriptions.append(message.sender.?);
            },
        }
    }
    fn notify_subscribers(self: *Self) !void {
        for (self.subscriptions.items) |actor| {
            try actor.send(
                self.ctx.actor,
                ConnectionMessage{
                    .ohlc_update = self.ohlc_list,
                },
            );
        }
    }
};
