const std = @import("std");
const backstage = @import("backstage");
const shared_models = @import("shared_models");
const xevtcp = @import("xevtcp");
const type_utils = @import("../utils/type_utils.zig");
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Orderbook = shared_models.OrderBook;
const OHLCList = shared_models.OHLCList;
const stringifyOHLCList = shared_models.stringifyOHLCList;
const OrderbookMessage = @import("../trading/orderbook_actor.zig").OrderbookMessage;
const OHLCMessage = @import("../trading/ohlc_actor.zig").OHLCMessage;
const stringify = @import("zbor").stringify;
const parse = @import("zbor").parse;
const DataItem = @import("zbor").DataItem;
const ClientConnection = xevtcp.ClientConnection;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

// TODO: This is the wrong place for this
pub const MessageTypes = enum {
    orderbook,
    ohlc,
};

pub const ConnectionMessage = union(enum) {
    orderbook_update: *Orderbook,
    ohlc_update: OHLCList,
    setup: SetupMessage,
};

pub const SetupMessage = struct {
    client_conn: *ClientConnection,
    close_context: *anyopaque,
    close_callback: *const fn (self: *anyopaque, conn: *ConnectionActor) anyerror!void,
};

pub const InitMessage = struct {};

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    client_conn: *ClientConnection = undefined,

    return_connection_context: *anyopaque = undefined,
    return_connection: *const fn (self: *anyopaque, conn: *Self) anyerror!void = undefined,

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

    pub fn deinit(_: *Self) void {
        // TODO: add proper deinit
    }

    pub fn receive(self: *Self, message: *const Envelope(ConnectionMessage)) !void {
        switch (message.payload) {
            .setup => |m| {
                self.client_conn = m.client_conn;
                self.client_conn.setCloseCallback(@ptrCast(self), close);
                self.return_connection_context = m.close_context;
                self.return_connection = m.close_callback;
                self.read();
            },
            .orderbook_update => |m| {
                const str = try m.stringify(self.allocator);
                std.debug.print("orderbook_update: {s} str length: {d}\n", .{ m.ticker, str.items.len });
                try self.write(.orderbook, str);
            },
            .ohlc_update => |m| {
                const str = try stringifyOHLCList(self.allocator, m);
                try self.write(.ohlc, str);
            },
        }
    }

    pub fn read(
        self: *Self,
    ) void {
        self.client_conn.read(@ptrCast(self), readCallback);
    }
    fn readCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) void {
        const self = unsafeAnyOpaqueCast(Self, self_);

        var it = std.mem.tokenizeAny(u8, payload, "\r\n");

        while (it.next()) |line| {
            if (std.mem.eql(u8, line, "start")) {
                self.ctx.send("BTC/USD_orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
                self.ctx.send("ETH/USD_orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
            }
        }
    }

    pub fn write(self: *Self, message_type: MessageTypes, buf: std.ArrayList(u8)) !void {
        try self.client_conn.write(MessageTypes, message_type, buf.items);
    }

    fn close(
        self_: ?*anyopaque,
    ) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);
        try self.ctx.send("BTC/USD_orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
        try self.ctx.send("ETH/USD_orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
        try self.return_connection(self.return_connection_context, self);
    }
};
