const std = @import("std");
const backstage = @import("backstage");
const ConnectionActor = @import("connection_actor.zig").ConnectionActor;
const ConnectionMessage = @import("connection_actor.zig").ConnectionMessage;
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

const xevtcp = @import("xevtcp");
const Server = xevtcp.Server;

pub const ServerMessage = union(enum) {
    init: InitMessage,
    listen: ListenMessage,
};

pub const InitMessage = struct {
    address: std.net.Address,
    max_connections: u31,
};
pub const ListenMessage = struct {};

pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    server: xevtcp.Server = undefined,
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

    pub fn receive(self: *Self, message: *const Envelope(ServerMessage)) !void {
        switch (message.payload) {
            .init => |m| {
                self.server = try xevtcp.Server.init(
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
            .listen => |_| {
                self.server.startAccepting();
            },
        }
    }

    fn acceptCallback(
        self_: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        client_conn: *xevtcp.ClientConnection,
    ) xev.CallbackAction {
        const self = unsafeAnyOpaqueCast(Self, self_);
        // This is a socket per connection -- DO NOT FORGET
        // const socket: xev.TCP = result catch {
        //     return .rearm;
        // };
        const fd_string = std.fmt.allocPrint(self.allocator, "{}", .{client_conn.socket.fd}) catch |err| {
            std.log.err("Failed to allocate string for socket fd {d}: {any}", .{ client_conn.socket.fd, err });
            // TODO: Close connection
            return .rearm;
        };
        
        const actor_interface = self.ctx.spawnChildActor(ConnectionActor, ConnectionMessage, .{
            .id = fd_string,
        }) catch |err| {
            std.log.err("Failed to spawn connection actor: {any}", .{err});
            // TODO: Close connection
            return .rearm;
        };
        actor_interface.send(self.ctx.actor, ConnectionMessage{ .setup = .{
            .client_conn = client_conn,
        } }) catch unreachable;

        return .rearm;
    }
    fn closeConnection(self_: *anyopaque, conn: *ConnectionActor) !void {
        const self = unsafeAnyOpaqueCast(Self, self_);

        conn.deinit();
        const could_remove = self.ctx.deinitChildActorByID(conn.ctx.actor_id);
        if (!could_remove) {
            return error.FailedToRemoveConnection;
        }
        std.debug.print("Closed connection\n", .{});
    }
};
