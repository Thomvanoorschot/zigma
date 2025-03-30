const std = @import("std");
const ws = @import("xevzocket");
const json_utils = @import("../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const backstage = @import("backstage");
const brkr_impl = @import("../trading/broker_impl.zig");
const Loop = backstage.xev.Loop;
const xev = backstage.xev;
const BrokerPayload = brkr_impl.BrokerPayload;
const OrderbookUpdate = brkr_impl.OrderbookUpdate;
const WsSubsribeRequest = ws_messages.WsSubsribeRequest;
const parseOrderbookMessage = ws_messages.parseOrderbookMessage;
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
    fn wsReadCb(context: *anyopaque, payload: []const u8) !void {
        const self: *Self = @ptrCast(@alignCast(context));
        try self.read(payload);
    }
    fn read(self: *Self, payload: []const u8) !void {
        // std.debug.print("Received text: {s}\n", .{payload});
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const orderbook_message = try parseOrderbookMessage(payload, arena_state.allocator());
        if (orderbook_message) |message| {
            switch (message) {
                .snapshot => |snapshot| {
                    try self.read_callback(self.callback_context, BrokerPayload{ .orderbook_update = try self.convertUpdateData(snapshot) });
                },
                .update => |update| {
                    try self.read_callback(self.callback_context, BrokerPayload{ .orderbook_update = try self.convertUpdateData(update) });
                },
            }
        }
    }

    fn convertUpdateData(self: *Self, update: ws_messages.UpdateMessage) !OrderbookUpdate {
        var orderbook_update = try brkr_impl.OrderbookUpdate.init(self.allocator);
        var arena = orderbook_update.arena_state.allocator();
        var symbol_copy: []const u8 = undefined;
        const item = update.data[0];
        if (item.symbol.len > 0) {
            symbol_copy = try arena.dupe(u8, item.symbol);
        } else {
            symbol_copy = "";
        }

        var converted_bids = try arena.alloc(brkr_impl.PriceLevel, item.bids.len);
        for (item.bids, 0..) |bid, bid_idx| {
            converted_bids[bid_idx] = brkr_impl.PriceLevel{
                .price = bid.price,
                .qty = bid.qty,
            };
        }

        var converted_asks = try arena.alloc(brkr_impl.PriceLevel, item.asks.len);
        for (item.asks, 0..) |ask, ask_idx| {
            converted_asks[ask_idx] = brkr_impl.PriceLevel{
                .price = ask.price,
                .qty = ask.qty,
            };
        }

        var timestamp_copy: ?[]const u8 = null;
        if (item.timestamp) |ts| {
            timestamp_copy = try arena.dupe(u8, ts);
        }

        orderbook_update.data.* = brkr_impl.UpdateData{
            .symbol = symbol_copy,
            .bids = converted_bids,
            .asks = converted_asks,
            .timestamp = timestamp_copy,
            .checksum = item.checksum,
        };
        return orderbook_update;
    }
};
