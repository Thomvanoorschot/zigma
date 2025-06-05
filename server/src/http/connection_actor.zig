const std = @import("std");
const backstage = @import("backstage");
const shared_models = @import("shared_models");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Orderbook = shared_models.Orderbook;
const WsMessage = shared_models.WsMessage;
const ConnectionActorMessage = shared_models.ConnectionActor;

const OrderbookActorMessage = shared_models.OrderbookActor;
const ClientConnection = async_zocket.ClientConnection;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context = undefined,
    client_conn: *ClientConnection = undefined,
    subscribed_to_orderbooks: std.ArrayList([]const u8),

    const Self = @This();
    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .subscribed_to_orderbooks = std.ArrayList([]const u8).init(allocator),
        };
        return self;
    }

    pub fn setup(self: *Self, client_conn: *ClientConnection) void {
        self.client_conn = client_conn;
        self.client_conn.setCloseCallback(@ptrCast(self), closeCallback);
        self.client_conn.setReadCallback(@ptrCast(self), readCallback);
        self.client_conn.read();
    }

    pub fn deinit(self: *Self) !void {
        try self.ctx.deinit();
        for (self.subscribed_to_orderbooks.items) |ticker| {
            std.debug.print("unsubscribing from {s}\n", .{ticker});
            const msg = OrderbookActorMessage{ .message = .{ .unsubscribe = .{} } };
            const msg_bytes = try msg.encode(self.allocator);
            try self.ctx.send(ticker, msg_bytes);
            self.allocator.free(msg_bytes);
        }
    }

    pub fn receive(self: *Self, message: []const u8) !void {
        const connection_msg: ConnectionActorMessage = try ConnectionActorMessage.decode(message, self.allocator);
        if (connection_msg.message == null) {
            return error.InvalidMessage;
        }
        switch (connection_msg.message.?) {
            .orderbook_update => |ob| {
                const str = try WsMessage.encode(WsMessage{
                    .message = .{ .orderbook = ob },
                }, self.allocator);
                try self.write(str);
            },
            // .ohlc_update => |m| {
            //     const str = try stringifyOHLCList(self.allocator, m);
            //     // TODO Need to wrap the messages in a struct that holds a message type so that I can multiplex the messages
            //     try self.write(str);
            // },
            else => unreachable,
        }
    }

    fn readCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);

        var it = std.mem.tokenizeAny(u8, payload, "\r\n");

        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "open_orderbook:")) {
                const ticker = std.fmt.allocPrintZ(self.allocator, "{s}_orderbook_actor", .{line[15..]}) catch unreachable;
                // TODO: Need a better way to free this memory
                // defer self.allocator.free(ticker);
                const msg = OrderbookActorMessage{ .message = .{ .subscribe = .{} } };
                const msg_bytes = try msg.encode(self.allocator);
                self.ctx.send(ticker, msg_bytes) catch unreachable;
                self.allocator.free(msg_bytes);
                self.subscribed_to_orderbooks.append(ticker) catch unreachable;
            } else if (std.mem.startsWith(u8, line, "close_orderbook:")) {
                const ticker = std.fmt.allocPrintZ(self.allocator, "{s}_orderbook_actor", .{line[16..]}) catch unreachable;
                // TODO: Need a better way to free this memory
                // defer self.allocator.free(ticker);
                const msg = OrderbookActorMessage{ .message = .{ .unsubscribe = .{} } };
                const msg_bytes = try msg.encode(self.allocator);
                self.ctx.send(ticker, msg_bytes) catch unreachable;
                self.allocator.free(msg_bytes);

                for (self.subscribed_to_orderbooks.items, 0..) |t, i| {
                    if (std.mem.eql(u8, t, ticker)) {
                        _ = self.subscribed_to_orderbooks.orderedRemove(i);
                        break;
                    }
                }
            }
        }
    }

    pub fn write(self: *Self, buf: []const u8) !void {
        try self.client_conn.write(.binary, buf);
    }

    fn closeCallback(
        self_: ?*anyopaque,
    ) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);
        try self.deinit();
    }
};
