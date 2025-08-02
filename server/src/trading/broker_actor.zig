const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const orderbook_actor = @import("orderbook_actor.zig");
const ohlc_actor = @import("ohlc_actor.zig");
const shared_models = @import("shared_models");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

const xev = backstage.xev;
const Context = backstage.Context;
const BrokerImpl = brkr_impl.BrokerImpl;
const BrokerPayload = brkr_impl.BrokerPayload;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const BrokerActorMessage = shared_models.BrokerActor;
const OrderbookActorMessage = shared_models.OrderbookActor;
const OHLCActorMessage = shared_models.OHLCActor;

pub const BrokerType = enum {
    KRAKEN,
};

pub const MarketDataType = enum {
    ORDERBOOK,
    OHLC,
};

// @generate-proxy
pub const BrokerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    broker: ?BrokerImpl = null,
    completion: xev.Completion = undefined,

    const Self = @This();
    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
        };

        return self;
    }

    pub fn deinit(self: *Self) !void {
        if (self.broker) |*broker| {
            broker.deinit();
        }
    }

    pub fn setup(self: *Self, broker_type: BrokerType) void {
        self.broker = try BrokerImpl.init(
            self.allocator,
            self.ctx.getLoop(),
            broker_type,
            @ptrCast(self),
            readMessage,
        );
    }

    pub fn start(self: *Self, ticker: []const u8, market_data_type: MarketDataType) !void {
        switch (market_data_type) {
            .ORDERBOOK => try self.broker.?.subscribeToOrderbook(ticker),
            .OHLC => try self.broker.?.subscribeToOHLC(ticker),
            else => return error.UnsupportedMarketData,
        }
    }

    fn readMessage(context: *anyopaque, message: anyerror!?BrokerPayload) !void {
        const self = unsafeAnyOpaqueCast(Self, context);

        if (try message) |m| {
            switch (m) {
                .orderbook_update => |update| {
                    var topic_buf: [40]u8 = undefined;
                    const topic = try std.fmt.bufPrintZ(&topic_buf, "orderbook_updates_{s}", .{update.ticker.Owned.str});
                    try self.ctx.publishToTopic(topic, OrderbookActorMessage{
                        .message = .{ .update = update.* },
                    });
                },
                .ohlc_update => |update| {
                    var topic_buf: [40]u8 = undefined;
                    const topic = try std.fmt.bufPrintZ(&topic_buf, "ohlc_updates_{s}", .{update.ticker.Owned.str});
                    try self.ctx.publishToTopic(topic, OHLCActorMessage{
                        .message = .{ .update = update.* },
                    });
                },
            }
        }
    }
};
