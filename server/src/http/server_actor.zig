const std = @import("std");
const backstage = @import("backstage");
const ConnectionActor = @import("connection_actor.zig").ConnectionActor;
const ConnectionMessage = @import("connection_actor.zig").ConnectionMessage;
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

const wire = @import("wire");
const Server = wire.Server;
const ClientConnection = wire.ClientConnection;

pub const ServerMessage = union(enum) {
    init: InitMessage,
    accept: AcceptMessage,
};

pub const InitMessage = struct {
    address: std.net.Address,
    max_connections: u31,
};
pub const AcceptMessage = struct {};

pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    server: Server = undefined,
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
    }

    pub fn receive(self: *Self, message: *const Envelope(ServerMessage)) !void {
        switch (message.payload) {
            .init => |m| {
                self.server = try Server.init(
                    self.allocator,
                    self.ctx.getLoop(),
                    .{
                        .address = m.address,
                        .max_connections = m.max_connections,
                    },
                    self,
                    acceptCallback,
                );
            },
            .accept => |_| {
                self.server.accept();
            },
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
            client_conn.close(err);
            return .rearm;
        };

        const actor_interface = self.ctx.spawnChildActor(ConnectionActor, ConnectionMessage, .{
            .id = fd_string,
        }) catch |err| {
            client_conn.close(err);
            return .rearm;
        };
        actor_interface.send(self.ctx.actor, ConnectionMessage{ .setup = .{
            .client_conn = client_conn,
        } }) catch unreachable;

        return .rearm;
    }
};
