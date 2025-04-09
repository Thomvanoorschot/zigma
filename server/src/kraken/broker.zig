const std = @import("std");
const ws = @import("xevzocket");
const json_utils = @import("../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const backstage = @import("backstage");
const brkr_impl = @import("../trading/broker_impl.zig");
const obu = @import("../trading/orderbook_update.zig");
const ohclu = @import("../trading/ohcl_update.zig");
const xev = backstage.xev;
const Loop = xev.Loop;
const BrokerPayload = brkr_impl.BrokerPayload;
const OrderbookUpdate = obu.OrderbookUpdate;
const PriceLevel = obu.PriceLevel;
const UpdateData = obu.UpdateData;
const OHLCUpdate = ohclu.OHLCUpdate;
const WsSubsribeRequest = ws_messages.WsSubsribeRequest;
const parseMessage = ws_messages.parseMessage;
const BrokerImpl = brkr_impl.BrokerImpl;

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
        const self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .ws_client = try ws.Client.init(
                allocator,
                loop,
                try std.net.Address.parseIp4("127.0.0.1", 8080),
                wsReadCb,
                @ptrCast(self),
            ),
            .callback_context = callback_context,
            .read_callback = read_callback,
        };
        try self.ws_client.start();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
        self.ws_client.deinit();
    }

    pub fn subscribeToOrderbook(self: *Self, ticker: []const u8) !void {
        std.debug.print("Subscribing to orderbook for {s}\n", .{ticker});
        var buffer: [128]u8 = undefined;
        const req = try json_utils.jsonMarshalFixedBuffer(WsSubsribeRequest{
            .method = "subscribe",
            .params = .{
                .channel = "book",
                .symbol = &[_][]const u8{ticker},
            },
        }, &buffer);

        try self.ws_client.write(req);
    }

    pub fn subscribeToOHLC(self: *Self, ticker: []const u8) !void {
        std.debug.print("Subscribing to OHLC for {s}\n", .{ticker});
        var buffer: [128]u8 = undefined;
        const req = try json_utils.jsonMarshalFixedBuffer(WsSubsribeRequest{
            .method = "subscribe",
            .params = .{
                .channel = "ohlc",
                .symbol = &[_][]const u8{ticker},
            },
        }, &buffer);

        try self.ws_client.write(req);
    }

    fn wsReadCb(context: *anyopaque, payload: []const u8) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        try self.read(payload);
    }
    fn read(self: *Self, payload: []const u8) !void {
        // std.debug.print("Received text: {s}\n", .{payload});
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
                        .snapshot => |im| {
                            try self.read_callback(self.callback_context, BrokerPayload{
                                .ohlc_update = try self.convertOHLCUpdateData(im),
                            });
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

    fn convertUpdateData(self: *Self, update: ws_messages.OrderbookUpdateMessage) !OrderbookUpdate {
        var orderbook_update = try OrderbookUpdate.init(self.allocator);
        var arena = orderbook_update.arena_state.allocator();
        var symbol_copy: []const u8 = undefined;
        const item = update.data[0];
        if (item.symbol.len > 0) {
            symbol_copy = try arena.dupe(u8, item.symbol);
        } else {
            symbol_copy = "";
        }

        var converted_bids = try arena.alloc(PriceLevel, item.bids.len);
        for (item.bids, 0..) |bid, bid_idx| {
            converted_bids[bid_idx] = PriceLevel{
                .price = bid.price,
                .qty = bid.qty,
            };
        }

        var converted_asks = try arena.alloc(PriceLevel, item.asks.len);
        for (item.asks, 0..) |ask, ask_idx| {
            converted_asks[ask_idx] = PriceLevel{
                .price = ask.price,
                .qty = ask.qty,
            };
        }

        var timestamp_copy: ?[]const u8 = null;
        if (item.timestamp) |ts| {
            timestamp_copy = try arena.dupe(u8, ts);
        }

        orderbook_update.data.* = UpdateData{
            .symbol = symbol_copy,
            .bids = converted_bids,
            .asks = converted_asks,
            .timestamp = timestamp_copy,
            .checksum = item.checksum,
        };
        return orderbook_update;
    }

    fn convertOHLCUpdateData(self: *Self, update: ws_messages.OHLCUpdateMessage) !OHLCUpdate {
        var ohlc_update = try OHLCUpdate.init(self.allocator);
        var arena = ohlc_update.arena_state.allocator();
        var symbol_copy: []const u8 = undefined;
        const item = update.data[0];
        if (item.symbol.len > 0) {
            symbol_copy = try arena.dupe(u8, item.symbol);
        } else {
            symbol_copy = "";
        }
        var timestamp_copy: []const u8 = undefined;
        timestamp_copy = try arena.dupe(u8, item.timestamp);

        ohlc_update.data.* = ohclu.UpdateData{
            .symbol = symbol_copy,
            .open = item.open,
            .high = item.high,
            .low = item.low,
            .close = item.close,
            .trades = item.trades,
            .volume = item.volume,
            .interval = item.interval,
            .timestamp = timestamp_copy,
        };
        return ohlc_update;
    }
};
