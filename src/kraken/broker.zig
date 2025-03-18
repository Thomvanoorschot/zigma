const std = @import("std");
const ws = @import("websocket");
const json_utils = @import("../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const alphazig = @import("alphazig");
const brkr_impl = @import("../trading/broker_impl.zig");

const concurrency = alphazig.concurrency;
const Coroutine = concurrency.Coroutine;
const BrokerMessage = brkr_impl.BrokerMessage;
const OrderbookUpdate = brkr_impl.OrderbookUpdate;
const WsSubsribeRequest = ws_messages.WsSubsribeRequest;
const parseOrderbookMessage = ws_messages.parseOrderbookMessage;
pub const Broker = struct {
    allocator: std.mem.Allocator,
    ws_client: ws.Client,
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);

        var client = try ws.Client.init(allocator, .{ .host = "ws.kraken.com", .port = 443, .tls = true });
        try client.handshake("/v2", .{
            .timeout_ms = 5000,
            .headers = "Host: ws.kraken.com\r\nOrigin: https://www.kraken.com",
        });
        errdefer client.deinit();

        self.* = .{ .allocator = allocator, .ws_client = client };
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

    pub fn readMessage(self: *Self) !?BrokerMessage {
        const ws_msg = try self.ws_client.read();
        if (ws_msg) |msg| {
            var arena_state = std.heap.ArenaAllocator.init(self.allocator);
            defer arena_state.deinit();
            const orderbook_message = try parseOrderbookMessage(msg.data, arena_state.allocator());
            if (orderbook_message) |message| {
                switch (message) {
                    .snapshot => |snapshot| {
                        return BrokerMessage{ .orderbook_update = try self.convertUpdateData(snapshot) };
                    },
                    .update => |update| {
                        return BrokerMessage{ .orderbook_update = try self.convertUpdateData(update) };
                    },
                }
            }
        }
        return null;
    }

    fn convertUpdateData(self: *Self, update: ws_messages.UpdateMessage) !OrderbookUpdate {
        var orderbook_update = try brkr_impl.OrderbookUpdate.init(self.allocator, update.data.len);
        var arena = orderbook_update.arena_state.allocator();
        var converted_data = try arena.alloc(brkr_impl.UpdateData, update.data.len);
        for (update.data, 0..) |item, i| {
            var symbol_copy: []const u8 = undefined;
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

            converted_data[i] = brkr_impl.UpdateData{
                .symbol = symbol_copy,
                .bids = converted_bids,
                .asks = converted_asks,
                .timestamp = timestamp_copy,
            };
        }
        orderbook_update.data = converted_data;
        return orderbook_update;
    }
};
