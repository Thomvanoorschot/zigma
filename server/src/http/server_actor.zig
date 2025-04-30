const std = @import("std");
const backstage = @import("backstage");
const ConnectionActor = @import("connection_actor.zig").ConnectionActor;
const ConnectionMessage = @import("connection_actor.zig").ConnectionMessage;
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;

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
    socket: ?xev.TCP = null,
    max_connections: usize = 1024,
    accept_completion: xev.Completion = undefined,

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
                self.socket = try xev.TCP.init(m.address);
                self.max_connections = m.max_connections;
                try self.socket.?.bind(m.address);
                try self.socket.?.listen(m.max_connections);
            },
            .listen => |_| {
                std.log.info("Received 'listen' message (already listening).", .{});
                self.socket.?.accept(self.ctx.getLoop(), &self.accept_completion, Self, self, acceptCallback);
            },
        }
    }

    fn acceptCallback(
        self_: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        const self = self_ orelse unreachable;
        // This is a socket per connection -- DO NOT FORGET
        const socket: xev.TCP = result catch {
            return .rearm;
        };
        const fd_string = std.fmt.allocPrint(self.allocator, "{}", .{socket.fd}) catch |err| {
            std.log.err("Failed to allocate string for socket fd {d}: {any}", .{ socket.fd, err });
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
        const actor = unsafeAnyOpaqueCast(ConnectionActor, actor_interface.ptr);
        actor.socket = socket;
        actor.close_context = self;
        actor.close_callback = closeConnection;

        const connection_count = self.ctx.child_actors.count();
        std.debug.print("Accepted TCP connection\nconnections: {d}\n", .{connection_count});
        if (connection_count >= self.max_connections) {
            std.log.warn("Connection limit reached ({d}), rejecting new connection", .{self.max_connections});
            closeConnection(self, actor) catch unreachable;
            return .rearm;
        }

        actor.read();
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
