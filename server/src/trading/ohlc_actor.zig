const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const shared_models = @import("shared_models");
const date_utils = @import("../utils/date_utils.zig");

const OHLCActorMessage = shared_models.OHLCActor;
const OHLCList = shared_models.OHLCList;
const BrokerActorMessage = shared_models.BrokerActor;
const OHLCUpdate = shared_models.OHLCUpdate;
const OHLC = shared_models.OHLC;
const ConnectionActorMessage = shared_models.ConnectionActor;

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const Envelope = backstage.Envelope;

pub const OHLCActor = struct {
    allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    ctx: *Context,
    ohlc_list: OHLCList,
    subscriptions: std.ArrayList([]const u8),
    notify_subscribers_completion: xev.Completion = undefined,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();

        self.* = .{
            .allocator = allocator,
            .arena_state = arena_state,
            .ctx = ctx,
            .subscriptions = std.ArrayList([]const u8).init(allocator),
            .ohlc_list = OHLCList.init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        self.arena_state.deinit();
        try self.ctx.shutdown();
    }

    pub fn receive(self: *Self, message: Envelope) !void {
        const ohlc_msg: OHLCActorMessage = try OHLCActorMessage.decode(message.payload, self.allocator);
        if (ohlc_msg.message == null) {
            return error.InvalidMessage;
        }
        switch (ohlc_msg.message.?) {
            .start => |m| {
                const subscribe_msg = BrokerActorMessage{ .message = .{ .ohlc_subscribe = .{ .ticker = m.ticker } } };
                const subscribe_msg_bytes = try subscribe_msg.encode(self.allocator);
                defer self.allocator.free(subscribe_msg_bytes);
                try self.ctx.send("kraken_broker_actor", subscribe_msg_bytes);
                try self.ctx.runContinuously(
                    Self,
                    notify_subscribers,
                    &self.notify_subscribers_completion,
                    self,
                    20,
                );
            },
            .update => |m| {
                var ohlc_update: OHLCUpdate = m;
                const timestamp_unix = try date_utils.DateTime.parse(ohlc_update.timestamp.Owned.str, .rfc3339);
                const ohlc = OHLC{
                    .symbol = ohlc_update.symbol,
                    .open = ohlc_update.open,
                    .high = ohlc_update.high,
                    .low = ohlc_update.low,
                    .close = ohlc_update.close,
                    .trades = ohlc_update.trades,
                    .volume = ohlc_update.volume,
                    .interval = ohlc_update.interval,
                    .timestamp = ohlc_update.timestamp,
                    .timestamp_unix = @intCast(timestamp_unix.unix(.seconds)),
                };
                if (self.ohlc_list.ohlc.getLastOrNull()) |last| {
                    if (std.mem.eql(u8, last.timestamp.Owned.str, ohlc.timestamp.Owned.str)) {
                        // TODO: Probably more effecient to update the last item
                        _ = self.ohlc_list.ohlc.pop();
                        try self.ohlc_list.ohlc.append(ohlc);
                    } else {
                        try self.ohlc_list.ohlc.append(ohlc);
                    }
                } else {
                    try self.ohlc_list.ohlc.append(ohlc);
                }
                ohlc_update.deinit();
            },
            .subscribe => |_| {
                try self.subscriptions.append(try self.allocator.dupe(u8, message.senderID.?));
            },
            .unsubscribe => |_| {
                for (self.subscriptions.items, 0..) |actor_id, i| {
                    if (std.mem.eql(u8, actor_id, message.senderID.?)) {
                        _ = self.subscriptions.orderedRemove(i);
                        self.allocator.free(actor_id);
                        break;
                    }
                }
            },
        }
    }
    fn notify_subscribers(self: *Self) !void {
        for (self.subscriptions.items) |actorID| {
            const ohlc_update_msg = ConnectionActorMessage{ .message = .{ .ohlc_update = self.ohlc_list } };
            const ohlc_update_msg_bytes = try ohlc_update_msg.encode(self.allocator);
            defer self.allocator.free(ohlc_update_msg_bytes);
            try self.ctx.send(actorID, ohlc_update_msg_bytes);
        }
    }
};
