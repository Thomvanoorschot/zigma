const std = @import("std");
const ws = @import("async_zocket");
const json_utils = @import("../../../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const backstage = @import("backstage");
const brkr_impl = @import("../../broker_impl.zig");
const unsafeAnyOpaqueCast = @import("../../../utils/type_utils.zig").unsafeAnyOpaqueCast;
const OrderbookUpdate = @import("../../types/orderbook_update.zig").OrderbookUpdate;
const OHLCUpdate = @import("../../types/ohlc_update.zig").OHLCUpdate;
const OrderbookLevel = @import("../../types/orderbook_level.zig").OrderbookLevel;

const xev = backstage.xev;
const Loop = xev.Loop;
const BrokerPayload = brkr_impl.BrokerPayload;
const WsSubsribeRequest = ws_messages.WsSubscribeRequest;
const parseMessage = ws_messages.parseMessage;

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
                    .host = "ws.kraken.com",
                    .port = 443,
                    .path = "/v2",
                    .use_tls = true,
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
            try converted_bids.append(.{ .price = bid.price, .qty = bid.qty });
        }

        var converted_asks = std.ArrayList(OrderbookLevel).init(self.allocator);
        for (item.asks) |ask| {
            try converted_asks.append(.{ .price = ask.price, .qty = ask.qty });
        }
        const obu = try self.allocator.create(OrderbookUpdate);
        obu.* = .{
            .ticker = item.symbol,
            .bids = converted_bids,
            .asks = converted_asks,
            .checksum = item.checksum,
            .timestamp = if (item.timestamp != null) item.timestamp.? else null,
        };
        return obu;
    }

    fn convertOHLCUpdateData(self: *Self, update: ws_messages.OHLCUpdateMessage) !*OHLCUpdate {
        const item = update.data[0];
        const ohlc = try self.allocator.create(OHLCUpdate);
        ohlc.* = .{
            .ticker = item.symbol,
            .open = item.open,
            .high = item.high,
            .low = item.low,
            .close = item.close,
            .trades = item.trades,
            .volume = item.volume,
            .interval = item.interval,
            .timestamp = item.timestamp,
        };
        return ohlc;
    }
};
