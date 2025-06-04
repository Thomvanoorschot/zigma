const std = @import("std");
const ws = @import("async_zocket");
const json_utils = @import("../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const backstage = @import("backstage");
const brkr_impl = @import("../trading/broker_impl.zig");
const orderbook_proto = @import("../actor_message/orderbook.pb.zig");
const ohlc_proto = @import("../actor_message/ohlc.pb.zig");
const shared_models = @import("shared_models");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

const xev = backstage.xev;
const Loop = xev.Loop;
const BrokerPayload = brkr_impl.BrokerPayload;
const OrderbookUpdate = orderbook_proto.OrderbookUpdate;
const OrderbookLevel = orderbook_proto.OrderbookLevel;
const OHLCUpdate = ohlc_proto.OHLCUpdate;
const WsSubsribeRequest = ws_messages.WsSubscribeRequest;
const parseMessage = ws_messages.parseMessage;
const ManagedString = shared_models.ManagedString;

var broker: ?*Broker = null;
pub const Broker = struct {
    allocator: std.mem.Allocator,
    ws_client: ws.Client,
    callback_context: *anyopaque,
    read_callback: *const fn (*anyopaque, anyerror!?BrokerPayload) anyerror!void,
    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        loop: *Loop,
        callback_context: *anyopaque,
        comptime read_callback: *const fn (*anyopaque, anyerror!?BrokerPayload) anyerror!void,
    ) !*Self {
        if (broker) |b| {
            return b;
        }
        const self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .ws_client = try ws.Client.init(
                allocator,
                loop,
                .{
                    .host = "127.0.0.1",
                    .port = 8080,
                    .path = "/ws",
                },
                wsReadCb,
                @ptrCast(self),
            ),
            .callback_context = callback_context,
            .read_callback = read_callback,
        };
        std.log.info("Connecting to kraken", .{});
        self.ws_client.connect();
        self.ws_client.read();
        broker = self;
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
        self.ws_client.deinit();
    }

    pub fn subscribeToOrderbook(self: *Self, ticker: []const u8) !void {
        std.log.info("Subscribing to orderbook for {s}", .{ticker});
        var buffer: [128]u8 = undefined;
        const req = try ws_messages.stringifySubscribeRequestFixed(WsSubsribeRequest{
            .method = "subscribe",
            .params = .{
                .orderbook = .{
                    .channel = "book",
                    .symbol = &[_][]const u8{ticker},
                },
            },
        }, &buffer);

        try self.ws_client.write(req);
    }

    pub fn subscribeToOHLC(self: *Self, ticker: []const u8) !void {
        std.log.info("Subscribing to OHLC for {s}", .{ticker});
        var buffer: [128]u8 = undefined;
        const req = try ws_messages.stringifySubscribeRequestFixed(WsSubsribeRequest{
            .method = "subscribe",
            .params = .{
                .ohlc = .{
                    .channel = "ohlc",
                    .symbol = &[_][]const u8{ticker},
                    .interval = 1,
                },
            },
        }, &buffer);
        try self.ws_client.write(req);
    }

    fn wsReadCb(context: *anyopaque, payload: []const u8) !void {
        const self = unsafeAnyOpaqueCast(Self, context);
        try self.read(payload);
    }
    fn read(self: *Self, payload: []const u8) !void {
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const message = try parseMessage(arena_state.allocator(), payload);
        if (message) |m| {
            switch (m) {
                .orderbook => |obm| {
                    switch (obm) {
                        .snapshot => |im| {
                            try self.read_callback(self.callback_context, BrokerPayload{
                                .orderbook_update = try self.convertOrderbookUpdateData(im),
                            });
                        },
                        .update => |im| {
                            try self.read_callback(self.callback_context, BrokerPayload{
                                .orderbook_update = try self.convertOrderbookUpdateData(im),
                            });
                        },
                    }
                },
                .ohlc => |ohlc| {
                    switch (ohlc) {
                        .snapshot => |_| {
                            // try self.read_callback(self.callback_context, BrokerPayload{
                            //     .ohlc_update = try self.convertOHLCUpdateData(im),
                            // });
                        },
                        .update => |im| {
                            try self.read_callback(self.callback_context, BrokerPayload{
                                .ohlc_update = try self.convertOHLCUpdateData(im),
                            });
                        },
                    }
                },
            }
        }
    }

    fn convertOrderbookUpdateData(self: *Self, update: ws_messages.OrderbookUpdateMessage) !*OrderbookUpdate {
        const item = update.data[0];

        var converted_bids = std.ArrayList(OrderbookLevel).init(self.allocator);
        for (item.bids) |bid| {
            try converted_bids.append(.{ .price = bid.price, .size = bid.qty });
        }

        var converted_asks = std.ArrayList(OrderbookLevel).init(self.allocator);
        for (item.asks) |ask| {
            try converted_asks.append(.{ .price = ask.price, .size = ask.qty });
        }
        const obu = try self.allocator.create(OrderbookUpdate);
        obu.* = .{
            .symbol = try ManagedString.copy(item.symbol, self.allocator),
            .bids = converted_bids,
            .asks = converted_asks,
            .checksum = item.checksum,
            .timestamp = if (item.timestamp != null) try ManagedString.copy(item.timestamp.?, self.allocator) else null,
        };
        return obu;
    }

    fn convertOHLCUpdateData(self: *Self, update: ws_messages.OHLCUpdateMessage) !*OHLCUpdate {
        const item = update.data[0];
        const ohlc = try self.allocator.create(OHLCUpdate);
        ohlc.* = .{
            .symbol = try ManagedString.copy(item.symbol, self.allocator),
            .open = item.open,
            .high = item.high,
            .low = item.low,
            .close = item.close,
            .trades = item.trades,
            .volume = item.volume,
            .interval = item.interval,
            .timestamp = try ManagedString.copy(item.timestamp, self.allocator),
        };
        return ohlc;
    }
};
