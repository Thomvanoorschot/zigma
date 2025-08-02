const std = @import("std");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const brkr_actr = @import("broker_actor.zig");
const conn_actr = @import("../http/connection_actor.zig");
const date_utils = @import("../utils/date_utils.zig");
const BrokerActorProxy = @import("../generated/broker_actor_proxy.gen.zig").BrokerActorProxy;
const OHLCActorProxy = @import("../generated/ohlc_actor_proxy.gen.zig").OHLCActorProxy;
const OHLCList = @import("types/ohlc_list.zig").OHLCList;
const OHLCUpdate = @import("types/ohlc_update.zig").OHLCUpdate;
const OHLC = @import("types/ohlc.zig").OHLC;

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const Envelope = backstage.Envelope;
const newSubscriber = backstage.newSubscriber;

// @generate-proxy
pub const OHLCActor = struct {
    allocator: Allocator,
    arena_state: std.heap.ArenaAllocator,
    ctx: *Context,
    ohlc_list: OHLCList,
    const Self = @This();
    pub fn init(ctx: *Context, allocator: Allocator) !*Self {
        const self = try allocator.create(Self);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        errdefer arena_state.deinit();

        self.* = .{
            .allocator = allocator,
            .arena_state = arena_state,
            .ctx = ctx,
            .ohlc_list = OHLCList.init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        self.arena_state.deinit();
        self.ohlc_list.ohlc.deinit();
    }

    pub fn start(self: *Self, ticker: []const u8) !void {
        const broker_actor = try self.ctx.getActor(BrokerActorProxy, "kraken_broker_actor");
        try broker_actor.start(ticker, .OHLC);

        var topic_buf: [40]u8 = undefined;
        const stream_id = try std.fmt.bufPrintZ(&topic_buf, "ohlc_updates_{s}", .{ticker});
        const stream = try self.ctx.getStream(OHLCUpdate, stream_id);
        try stream.subscribe(newSubscriber(self.ctx.actor_id, OHLCActorProxy.Method.update));
        // try self.ctx.subscribeToActorTopic("kraken_broker_actor", stream_id);
    }

    pub fn update(self: *Self, u: OHLCUpdate) !void {
        const timestamp_unix = try date_utils.DateTime.parse(u.timestamp, .rfc3339);
        const ohlc = OHLC{
            .open = u.open,
            .high = u.high,
            .low = u.low,
            .close = u.close,
            .trades = u.trades,
            .volume = u.volume,
            .interval = u.interval,
            .timestamp = u.timestamp,
            .timestamp_unix = @intCast(timestamp_unix.unix(.seconds)),
        };
        if (self.ohlc_list.ohlc.getLastOrNull()) |last| {
            if (std.mem.eql(u8, last.timestamp, u.timestamp)) {
                // TODO: Probably more effecient to update the last item
                _ = self.ohlc_list.ohlc.pop();
                try self.ohlc_list.ohlc.append(ohlc);
            } else {
                try self.ohlc_list.ohlc.append(ohlc);
            }
        } else {
            try self.ohlc_list.ohlc.append(ohlc);
        }
        var stream_buf: [40]u8 = undefined;
        const stream_id = try std.fmt.bufPrintZ(&stream_buf, "{s}_ohlc_actor", .{self.ohlc_list.ticker});
        const stream = try self.ctx.getStream(OHLCList, stream_id);
        try stream.next(self.ohlc_list);
    }
};