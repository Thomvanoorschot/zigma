const std = @import("std");
const backstage = @import("backstage");
const shared_models = @import("shared_models");
const wire = @import("wire");
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
const ClientConnection = wire.ClientConnection;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

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
};

pub const InitMessage = struct {};

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    client_conn: *ClientConnection = undefined,

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
        try self.ctx.deinit();
        try self.ctx.send("BTC/USD_orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
        try self.ctx.send("ETH/USD_orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
        try self.ctx.send("XRP/USD_orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
        try self.ctx.send("ADA/USD_orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
    }

    pub fn receive(self: *Self, message: *const Envelope(ConnectionMessage)) !void {
        switch (message.payload) {
            .setup => |m| {
                self.client_conn = m.client_conn;
                self.client_conn.setCloseCallback(@ptrCast(self), close);
                self.read();
            },
            .orderbook_update => |m| {
                const str = try m.stringify(self.allocator);
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
                self.ctx.send("ETH/USD_orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
                self.ctx.send("BTC/USD_orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
                self.ctx.send("XRP/USD_orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
                self.ctx.send("ADA/USD_orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
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
        try self.deinit();
    }
};
