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
const ServerMessage = shared_models.ServerMessage;
const ConnectionActorMessage = shared_models.ConnectionActor;
const ClientMessage = shared_models.ClientMessage;
const OrderbookActorMessage = shared_models.OrderbookActor;
const OHLCActorMessage = shared_models.OHLCActor;
const ClientConnection = async_zocket.ClientConnection;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context = undefined,
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

    pub fn setup(self: *Self, client_conn: *ClientConnection) void {
        self.client_conn = client_conn;
        self.client_conn.setCloseCallback(@ptrCast(self), closeCallback);
        self.client_conn.setReadCallback(@ptrCast(self), readCallback);
        self.client_conn.read();
    }

    pub fn deinit(self: *Self) !void {
        try self.ctx.shutdown();
    }

    pub fn receive(self: *Self, envelope: Envelope) !void {
        const connection_msg: ConnectionActorMessage = try ConnectionActorMessage.decode(envelope.message, self.allocator);
        if (connection_msg.message == null) {
            return error.InvalidMessage;
        }

        switch (connection_msg.message.?) {
            .orderbook_update => |m| {
                const str = try ServerMessage.encode(ServerMessage{
                    .message = .{ .orderbook = m },
                }, self.allocator);
                try self.write(str);
            },
            .ohlc_update => |m| {
                const str = try ServerMessage.encode(ServerMessage{
                    .message = .{ .ohlc = m },
                }, self.allocator);
                try self.write(str);
            },
        }
    }

    fn readCallback(
        self_: ?*anyopaque,
        payload: []const u8,
    ) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);

        const client_msg: ClientMessage = try ClientMessage.decode(payload, self.allocator);
        if (client_msg.message == null) {
            return error.InvalidMessage;
        }
        switch (client_msg.message.?) {
            .subscribe => |m| {
                var actor_id_buf: [25]u8 = undefined;

                const actor_id = switch (m.subscription_type) {
                    .ORDERBOOK => blk: {
                        break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_orderbook_actor", .{m.ticker.Owned.str});
                    },
                    .OHLC => blk: {
                        break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_ohlc_actor", .{m.ticker.Owned.str});
                    },
                    else => unreachable,
                };
                try self.ctx.subscribeToActor(actor_id);
            },
            .unsubscribe => |m| {
                var actor_id_buf: [25]u8 = undefined;
                const actor_id = switch (m.subscription_type) {
                    .ORDERBOOK => blk: {
                        break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_orderbook_actor", .{m.ticker.Owned.str});
                    },
                    .OHLC => blk: {
                        break :blk try std.fmt.bufPrintZ(&actor_id_buf, "{s}_ohlc_actor", .{m.ticker.Owned.str});
                    },
                    else => unreachable,
                };
                try self.ctx.unsubscribeFromActor(actor_id);
            },
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
        try self.ctx.shutdown();
    }
};
