const std = @import("std");
const backstage = @import("backstage");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const Orderbook = @import("../trading/types/orderbook.zig").Orderbook;
const OHLCList = @import("../trading/types/ohlc_list.zig").OHLCList;
const shared_models = @import("shared_models");
const ServerActorProxy = @import("../generated/server_actor_proxy.gen.zig").ServerActorProxy;

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Server = async_zocket.Server;
const ClientConnection = async_zocket.ClientConnection;
const ClientMessage = shared_models.ClientMessage;
const ServerMessage = shared_models.ServerMessage;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;
const newSubscriber = backstage.newSubscriber;
const ProtobufOrderbook = shared_models.Orderbook;
const ProtobufOrderbookLevel = shared_models.OrderbookLevel;
const ManagedString = shared_models.ManagedString;

pub const ConnectionHandler = struct {
    client_conn: *ClientConnection,
    allocator: std.mem.Allocator,
    ctx: *Context,
    id: []const u8,
    server_actor: *ServerActor,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, ctx: *Context, client_conn: *ClientConnection, id: []const u8, server_actor: *ServerActor) !*ConnectionHandler {
        const self = try allocator.create(ConnectionHandler);
        self.* = .{
            .client_conn = client_conn,
            .allocator = allocator,
            .ctx = ctx,
            .id = try allocator.dupe(u8, id),
            .server_actor = server_actor,
        };

        client_conn.setCloseCallback(@ptrCast(self), closeCallback);
        client_conn.setReadCallback(@ptrCast(self), readCallback);

        return self;
    }

    pub fn deinit(self: *ConnectionHandler) void {
        self.allocator.free(self.id);
        self.allocator.destroy(self);
    }

    fn readCallback(self_: ?*anyopaque, payload: []const u8) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);

        const client_msg: ClientMessage = try ClientMessage.decode(payload, self.allocator);
        if (client_msg.message == null) {
            return error.InvalidMessage;
        }
        switch (client_msg.message.?) {
            .subscribe => |m| {
                try self.server_actor.subscribeConnection(self.id, m.ticker.Owned.str, m.subscription_type);
            },
            .unsubscribe => |m| {
                try self.server_actor.unsubscribeConnection(self.id, m.ticker.Owned.str, m.subscription_type);
            },
        }
    }

    fn toProtobufOrderbook(self: *Self, orderbook: Orderbook) !ProtobufOrderbook {
        var pb_orderbook = ProtobufOrderbook{
            .bids = std.ArrayList(ProtobufOrderbookLevel).init(self.allocator),
            .asks = std.ArrayList(ProtobufOrderbookLevel).init(self.allocator),
            .max_depth = orderbook.max_depth,
            .exchange = try ManagedString.copy(orderbook.exchange, self.allocator),
            .ticker = try ManagedString.copy(orderbook.ticker, self.allocator),
        };

        for (orderbook.bids.items) |bid| {
            try pb_orderbook.bids.append(ProtobufOrderbookLevel{
                .price = bid.price,
                .qty = bid.qty,
            });
        }

        for (orderbook.asks.items) |ask| {
            try pb_orderbook.asks.append(ProtobufOrderbookLevel{
                .price = ask.price,
                .qty = ask.qty,
            });
        }

        return pb_orderbook;
    }

    pub fn sendOrderbookUpdate(self: *ConnectionHandler, orderbook: Orderbook) !void {
        const server_msg = ServerMessage{
            .message = .{ .orderbook = try self.toProtobufOrderbook(orderbook) },
        };
        const str = try ServerMessage.encode(server_msg, self.allocator);
        defer self.allocator.free(str);
        try self.client_conn.write(.binary, str);
    }

    pub fn sendOHLCUpdate(self: *ConnectionHandler, ohlc: OHLCList) !void {
        // TODO Need to reimplement
        _ = self;
        _ = ohlc;
        // const server_msg = ServerMessage{
        //     .message = .{ .ohlc = ohlc },
        // };
        // const str = try ServerMessage.encode(server_msg, self.allocator);
        // defer self.allocator.free(str);
        // try self.client_conn.write(.binary, str);
    }

    fn closeCallback(self_: ?*anyopaque) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);
        self.server_actor.removeConnection(self.id) catch {};
    }
};

// @generate-proxy
pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    server: Server = undefined,
    connections: std.HashMap([]const u8, *ConnectionHandler, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    subscriptions: std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage),

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .connections = std.HashMap([]const u8, *ConnectionHandler, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .subscriptions = std.HashMap([]const u8, std.ArrayList([]const u8), std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.connections.deinit();

        var sub_iterator = self.subscriptions.iterator();
        while (sub_iterator.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.subscriptions.deinit();
    }

    pub fn setup(self: *Self, host: []const u8, port: u16, max_connections: u31) !void {
        self.server = try Server.init(
            self.allocator,
            self.ctx.getLoop(),
            .{
                .host = host,
                .port = port,
                .max_connections = max_connections,
                .use_tls = true,
                .cert_file = "server.crt",
                .key_file = "server.key",
            },
            self,
            acceptCallback,
        );
    }

    pub fn accept(self: *Self) !void {
        self.server.accept();
    }

    pub fn subscribeConnection(
        self: *Self,
        connection_id: []const u8,
        ticker: []const u8,
        subscription_type: shared_models.SubscriptionType,
    ) !void {
        var actor_id_buf: [40]u8 = undefined;

        switch (subscription_type) {
            .ORDERBOOK => {
                const stream_id = try std.fmt.bufPrintZ(&actor_id_buf, "{s}_orderbook_actor", .{ticker});
                const stream = try self.ctx.getStream(Orderbook, stream_id);
                try stream.subscribe(newSubscriber(self.ctx.actor_id, ServerActorProxy.Method.orderbookUpdated));
            },
            .OHLC => {
                const stream_id = try std.fmt.bufPrintZ(&actor_id_buf, "{s}_ohlc_actor", .{ticker});
                const stream = try self.ctx.getStream(OHLCList, stream_id);
                try stream.subscribe(newSubscriber(self.ctx.actor_id, ServerActorProxy.Method.ohlcUpdated));
            },
            else => unreachable,
        }

        const result = try self.subscriptions.getOrPut(try self.allocator.dupe(u8, connection_id));
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(try self.allocator.dupe(u8, ticker));
    }

    pub fn unsubscribeConnection(self: *Self, connection_id: []const u8, ticker: []const u8, subscription_type: shared_models.SubscriptionType) !void {
        // TODO Need to reimplement
        _ = self;
        _ = connection_id;
        _ = ticker;
        _ = subscription_type;
    }

    pub fn orderbookUpdated(self: *Self, orderbook: Orderbook) !void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            const connection = entry.value_ptr.*;
            connection.sendOrderbookUpdate(orderbook) catch |err| {
                std.log.err("Failed to send orderbook update to {s}: {any}", .{ entry.key_ptr.*, err });
            };
        }
    }

    pub fn ohlcUpdated(self: *Self, ohlc: OHLCList) !void {
        var iterator = self.connections.iterator();
        while (iterator.next()) |entry| {
            const connection = entry.value_ptr.*;
            connection.sendOHLCUpdate(ohlc) catch |err| {
                std.log.err("Failed to send OHLC update to {s}: {any}", .{ entry.key_ptr.*, err });
            };
        }
    }

    fn acceptCallback(
        self_: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        client_conn: *ClientConnection,
    ) xev.CallbackAction {
        const self = unsafeAnyOpaqueCast(Self, self_);
        const fd_string = std.fmt.allocPrint(self.allocator, "{}", .{client_conn.socket.fd}) catch |err| {
            std.log.err("Failed to print fd: {any}", .{err});
            client_conn.close();
            return .rearm;
        };
        defer self.allocator.free(fd_string);

        const connection = ConnectionHandler.init(self.allocator, self.ctx, client_conn, fd_string, self) catch |err| {
            std.log.err("Failed to create connection handler: {any}", .{err});
            client_conn.close();
            return .rearm;
        };

        self.connections.put(self.allocator.dupe(u8, fd_string) catch unreachable, connection) catch |err| {
            std.log.err("Failed to store connection: {any}", .{err});
            connection.deinit();
            client_conn.close();
            return .rearm;
        };

        client_conn.read();
        return .rearm;
    }

    pub fn removeConnection(self: *Self, connection_id: []const u8) !void {
        if (self.connections.fetchRemove(connection_id)) |kv| {
            self.allocator.free(kv.key);
            kv.value.deinit();
        }

        if (self.subscriptions.fetchRemove(connection_id)) |kv| {
            kv.value.deinit();
            self.allocator.free(kv.key);
        }
    }
};
