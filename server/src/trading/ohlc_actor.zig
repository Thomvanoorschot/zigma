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
const OHLC = shared_models.OHLC;
const ConnectionActorMessage = shared_models.ConnectionActor;

const xev = backstage.xev;
const ActorInterface = backstage.ActorInterface;
const Allocator = std.mem.Allocator;
const Context = backstage.Context;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;
const Envelope = backstage.Envelope;
const ManagedString = shared_models.ManagedString;

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
    }

    pub fn start(self: *Self, ticker: []const u8) !void {
        try self.ctx.send("kraken_broker_actor", BrokerActorMessage{
            .message = .{
                .start = .{
                    .ticker = ticker,
                    .market_data = .OHLC,
                },
            },
        });
        var topic_buf: [40]u8 = undefined;
        const topic = try std.fmt.bufPrintZ(&topic_buf, "ohlc_updates_{s}", .{ticker});
        try self.ctx.subscribeToActorTopic("kraken_broker_actor", topic);
    }

    pub fn update(self: *Self, u: OHLCUpdate) !void {
        const timestamp_unix = try date_utils.DateTime.parse(u.timestamp, .rfc3339);
        const ohlc = OHLC{
            .ticker = u.ticker,
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
        try self.ctx.publish(
            ConnectionActorMessage{ .message = .{ .ohlc_update = self.ohlc_list } },
        );
    }
};

pub const OHLCUpdate = struct {
    ticker: []const u8,
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    trades: u64,
    volume: f64,
    interval: u64,
    timestamp: []const u8,
};
