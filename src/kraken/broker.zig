const std = @import("std");
const ws = @import("websocket");
const json_utils = @import("../utils/json_utils.zig");
const ws_messages = @import("./ws_messages.zig");
const alphazig = @import("alphazig");

const concurrency = alphazig.concurrency;
const Coroutine = concurrency.Coroutine;
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
        // Coroutine(listenToOrderbook).go(self);
    }

    pub fn readMessages(self: *Self) !void {
        const ws_msg = try self.ws_client.read();
        if (ws_msg) |msg| {
            const orderbook_message = try parseOrderbookMessage(msg.data, self.allocator);
            if (orderbook_message) |message| {
                switch (message) {
                    .snapshot => |snapshot| {
                        std.debug.print("Orderbook message: {}\n", .{snapshot});
                    },
                    .update => |update| {
                        std.debug.print("Update message: {}\n", .{update});
                    },
                }
            }
        }
    }
};
