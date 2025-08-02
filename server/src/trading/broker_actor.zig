const std = @import("std");
const krkn = @import("exchanges/kraken/broker.zig");
const backstage = @import("backstage");
const brkr_impl = @import("broker_impl.zig");
const orderbook_actor = @import("orderbook_actor.zig");
const ohlc_actor = @import("ohlc_actor.zig");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;
const OrderbookUpdate = @import("types/orderbook_update.zig").OrderbookUpdate;
const OHLCUpdate = @import("types/ohlc_update.zig").OHLCUpdate;

const xev = backstage.xev;
const Context = backstage.Context;
const BrokerImpl = brkr_impl.BrokerImpl;
const BrokerPayload = brkr_impl.BrokerPayload;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const BrokerType = brkr_impl.BrokerType;
const MarketDataType = brkr_impl.MarketDataType;

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

    pub fn setup(self: *Self, broker_type: BrokerType) !void {
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
        }
    }

    fn readMessage(context: *anyopaque, message: anyerror!?BrokerPayload) !void {
        const self = unsafeAnyOpaqueCast(Self, context);

        if (try message) |m| {
            switch (m) {
                .orderbook_update => |update| {
                    var topic_buf: [40]u8 = undefined;
                    const topic = try std.fmt.bufPrintZ(&topic_buf, "orderbook_updates_{s}", .{update.ticker});
                    const stream = try self.ctx.getStream(OrderbookUpdate, topic);
                    try stream.next(update.*);
                },
                .ohlc_update => |update| {
                    var topic_buf: [40]u8 = undefined;
                    const topic = try std.fmt.bufPrintZ(&topic_buf, "ohlc_updates_{s}", .{update.ticker});
                    const stream = try self.ctx.getStream(OHLCUpdate, topic);
                    try stream.next(update.*);
                },
            }
        }
    }
};
