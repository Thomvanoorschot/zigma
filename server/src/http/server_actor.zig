const std = @import("std");
const backstage = @import("backstage");
const ConnectionActor = @import("connection_actor.zig").ConnectionActor;
const ConnectionMessage = @import("connection_actor.zig").ConnectionMessage;
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;

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
    connections: std.AutoHashMap(std.posix.socket_t, *ConnectionActor),
    max_connections: usize = 1024,
    accept_completion: xev.Completion = undefined,

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .connections = std.AutoHashMap(std.posix.socket_t, *ConnectionActor).init(allocator),
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

        const actor_interface = self.ctx.spawnChildActor(ConnectionActor, ConnectionMessage, .{
            .id = "connection_actor",
        }) catch unreachable;
        const actor: *ConnectionActor = @as(*ConnectionActor, @ptrCast(@alignCast(actor_interface.ptr)));
        actor.socket = socket;
        actor.close_context = self;
        actor.close_callback = closeConnection;
        // const conn = Connection.init(
        //     self.allocator,
        //     socket,
        //     l,
        //     @ptrCast(self),
        //     closeConnection,
        // ) catch |err| {
        //     std.log.err("Failed to initialize connection: {any}", .{err});
        //     return .rearm;
        // };

        std.debug.print("connections: {d}\n", .{self.connections.count()});
        if (self.connections.count() >= self.max_connections) {
            std.log.warn("Connection limit reached ({d}), rejecting new connection", .{self.max_connections});
            closeConnection(self, actor) catch unreachable;
            return .rearm;
        }

        self.connections.put(socket.fd, actor) catch |err| {
            std.log.err("Failed to append connection to list: {any}", .{err});
            closeConnection(self, actor) catch unreachable;
            return .rearm;
        };
        actor.read();
        return .rearm;
    }

    const closeContext = struct {
        self: *Self,
        conn: *ConnectionActor,
    };

    fn closeConnection(self_: *anyopaque, conn: *ConnectionActor) !void {
        const self: *Self = @ptrCast(@alignCast(self_));

        const close_context = try self.allocator.create(closeContext);
        conn.close_completion = .{
            .op = .{ .close = .{ .fd = conn.socket.fd } },
            .userdata = close_context,
            .callback = closeCallback,
        };
        close_context.* = .{
            .self = self,
            .conn = conn,
        };
        self.ctx.getLoop().add(&conn.close_completion);
    }

    fn closeCallback(
        ctx_: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.Result,
    ) xev.CallbackAction {
        const ctx: *closeContext = @ptrCast(@alignCast(ctx_));
        _ = ctx.self.connections.remove(ctx.conn.socket.fd);
        ctx.self.allocator.destroy(ctx.conn);
        ctx.self.allocator.destroy(ctx);
        std.debug.print("Closed connection\n", .{});
        return .disarm;
    }
};
