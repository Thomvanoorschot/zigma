const std = @import("std");
const ws = @import("async_zocket");
const json_utils = @import("../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const backstage = @import("backstage");
const brkr_impl = @import("../trading/broker_impl.zig");
const obu = @import("../trading/orderbook_update.zig");
const ohlcu = @import("../trading/ohlc_update.zig");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;
const xev = backstage.xev;
const Loop = xev.Loop;
const BrokerPayload = brkr_impl.BrokerPayload;
const OrderbookUpdate = obu.OrderbookUpdate;
const OHLCUpdate = ohlcu.OHLCUpdate;
const WsSubsribeRequest = ws_messages.WsSubscribeRequest;
const parseMessage = ws_messages.parseMessage;
const BrokerImpl = brkr_impl.BrokerImpl;

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
        try self.ws_client.connect();
        try self.ws_client.read();
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
                .orderbook => |ob| {
                    switch (ob) {
                        .snapshot => |im| {
                            try self.read_callback(self.callback_context, BrokerPayload{
                                .orderbook_update = try self.convertUpdateData(im),
                            });
                        },
                        .update => |im| {
                            try self.read_callback(self.callback_context, BrokerPayload{
                                .orderbook_update = try self.convertUpdateData(im),
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

    fn convertUpdateData(self: *Self, update: ws_messages.OrderbookUpdateMessage) !*OrderbookUpdate {
        const item = update.data[0];

        const converted_bids = try self.allocator.alloc([2]f64, item.bids.len);
        defer self.allocator.free(converted_bids);
        for (item.bids, 0..) |bid, bid_idx| {
            converted_bids[bid_idx] = .{ bid.price, bid.qty };
        }

        const converted_asks = try self.allocator.alloc([2]f64, item.asks.len);
        defer self.allocator.free(converted_asks);
        for (item.asks, 0..) |ask, ask_idx| {
            converted_asks[ask_idx] = .{ ask.price, ask.qty };
        }

        return try OrderbookUpdate.init(self.allocator, .{
            .symbol = item.symbol,
            .bids = converted_bids,
            .asks = converted_asks,
            .checksum = item.checksum,
            .timestamp = item.timestamp,
        });
    }

    fn convertOHLCUpdateData(self: *Self, update: ws_messages.OHLCUpdateMessage) !*OHLCUpdate {
        const item = update.data[0];
        return try OHLCUpdate.init(self.allocator, .{
            .symbol = item.symbol,
            .open = item.open,
            .high = item.high,
            .low = item.low,
            .close = item.close,
            .trades = item.trades,
            .volume = item.volume,
            .interval = item.interval,
            .timestamp = item.timestamp,
        });
    }
};
