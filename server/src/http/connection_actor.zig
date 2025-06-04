const std = @import("std");
const backstage = @import("backstage");
const shared_models = @import("shared_models");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const actor_message = @import("../actor_message/actor_message.pb.zig");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Orderbook = shared_models.Orderbook;
const WsMessage = shared_models.WsMessage;

const OrderbookActorMessage = actor_message.OrderbookActor.message_union;
const ClientConnection = async_zocket.ClientConnection;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub const MessageTypes = enum {
    orderbook,
    ohlc,
};

pub const ConnectionMessage = union(enum) {
    orderbook_update: *Orderbook,
    // ohlc_update: OHLCList,
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

    pub fn deinit(self: *Self) !void {
        try self.ctx.deinit();
        for (self.subscribed_to_orderbooks.items) |ticker| {
            std.debug.print("unsubscribing from {s}\n", .{ticker});
            try self.ctx.send(ticker, OrderbookActorMessage{
                .unsubscribe = .{},
            });
        }
    }

    pub fn receive(self: *Self, message: *const Envelope(ConnectionMessage)) !void {
        switch (message.payload) {
            .setup => |m| {
                self.client_conn = m.client_conn;
                self.client_conn.setCloseCallback(@ptrCast(self), closeCallback);
                self.client_conn.setReadCallback(@ptrCast(self), readCallback);
                self.client_conn.read();
            },
            .orderbook_update => |ob| {
                const str = try WsMessage.encode(WsMessage{
                    .message = .{ .orderbook = ob.* },
                }, self.allocator);
                try self.write(str);
            },
            // .ohlc_update => |m| {
            //     const str = try stringifyOHLCList(self.allocator, m);
            //     // TODO Need to wrap the messages in a struct that holds a message type so that I can multiplex the messages
            //     try self.write(str);
            // },
        }
    }

    fn readCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) void {
        const self = unsafeAnyOpaqueCast(Self, self_);

        var it = std.mem.tokenizeAny(u8, payload, "\r\n");

        while (it.next()) |line| {
            if (std.mem.startsWith(u8, line, "open_orderbook:")) {
                const ticker = std.fmt.allocPrintZ(self.allocator, "{s}_orderbook_actor", .{line[15..]}) catch unreachable;
                // TODO: Need a better way to free this memory
                // defer self.allocator.free(ticker);
                self.ctx.send(ticker, OrderbookActorMessage{ .subscribe = .{} }) catch unreachable;
                self.subscribed_to_orderbooks.append(ticker) catch unreachable;
            } else if (std.mem.startsWith(u8, line, "close_orderbook:")) {
                const ticker = std.fmt.allocPrintZ(self.allocator, "{s}_orderbook_actor", .{line[16..]}) catch unreachable;
                // TODO: Need a better way to free this memory
                // defer self.allocator.free(ticker);
                self.ctx.send(ticker, OrderbookActorMessage{ .unsubscribe = .{} }) catch unreachable;

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
