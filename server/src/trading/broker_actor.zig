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
const BrokerType = brkr_impl.BrokerType;
const BrokerPayload = brkr_impl.BrokerPayload;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const BrokerActorMessage = shared_models.BrokerActor;
const OrderbookActorMessage = shared_models.OrderbookActor;
const OHLCActorMessage = shared_models.OHLCActor;

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

        try self.ctx.shutdown();
    }

    pub fn receive(self: *Self, envelope: Envelope) !void {
        defer envelope.deinit(self.allocator);
        const broker_msg: BrokerActorMessage = try BrokerActorMessage.decode(envelope.message, self.allocator);
        defer broker_msg.deinit();
        if (broker_msg.message == null) {
            return error.InvalidMessage;
        }
        switch (broker_msg.message.?) {
            .init => |m| {
                self.broker = try BrokerImpl.init(
                    self.allocator,
                    self.ctx.getLoop(),
                    m.broker,
                    @ptrCast(self),
                    readMessage,
                );
            },
            .start => |m| {
                switch (m.market_data) {
                    .ORDERBOOK => try self.broker.?.subscribeToOrderbook(m.ticker.Owned.str),
                    .OHLC => try self.broker.?.subscribeToOHLC(m.ticker.Owned.str),
                    else => return error.UnsupportedMarketData,
                }
            },
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
