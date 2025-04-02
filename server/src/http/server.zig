const std = @import("std");
const backstage = @import("backstage");
const Connection = @import("connection.zig").Connection;

const xev = backstage.xev;
const Loop = backstage.xev.Loop;
pub const Options = struct {
    address: std.net.Address,
    max_connections: usize,
};

pub const Server = struct {
    allocator: std.mem.Allocator,
    socket: xev.TCP,
    connections: std.AutoHashMap(std.posix.socket_t, *Connection),
    max_connections: usize,
    loop: *Loop,
    accept_completion: xev.Completion = undefined,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, loop: *Loop, options: Options) !Self {
        const self = Self{
            .allocator = allocator,
            .socket = try xev.TCP.init(options.address),
            .connections = std.AutoHashMap(std.posix.socket_t, *Connection).init(allocator),
            .max_connections = options.max_connections,
            .loop = loop,
        };
        try self.socket.bind(options.address);
        try self.socket.listen(1024);
        return self;
    }

    pub fn listen(self: *Self) !void {
        self.socket.accept(self.loop, &self.accept_completion, Self, self, acceptCallback);
    }
    pub fn deinit(self: *Self) void {
        const posix = std.posix;
        posix.close(self.socket.fd);
    }

    fn acceptCallback(
        self: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        // This is a socket per connection -- DO NOT FORGET
        const socket: xev.TCP = result catch {
            return .rearm;
        };

        const conn = Connection.init(
            self.?.connections.allocator,
            socket,
            self.?.loop,
            @ptrCast(self),
            closeConnection,
        ) catch |err| {
            std.log.err("Failed to initialize connection: {any}", .{err});
            return .rearm;
        };

        std.debug.print("connections: {d}\n", .{self.?.connections.count()});
        if (self.?.connections.count() >= self.?.max_connections) {
            std.log.warn("Connection limit reached ({d}), rejecting new connection", .{self.?.max_connections});
            closeConnection(self.?, conn) catch unreachable;
            return .rearm;
        }

        self.?.connections.put(socket.fd, conn) catch |err| {
            std.log.err("Failed to append connection to list: {any}", .{err});
            closeConnection(self.?, conn) catch unreachable;
            return .rearm;
        };
        conn.read();
        return .rearm;
    }

    const closeContext = struct {
        self: *Self,
        conn: *Connection,
    };

    fn closeConnection(self_: *anyopaque, conn: *Connection) !void {
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
        self.loop.add(&conn.close_completion);
    }

    fn closeCallback(
        close_context: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.Result,
    ) xev.CallbackAction {
        const ctx: *closeContext = @ptrCast(@alignCast(close_context));
        _ = ctx.self.connections.remove(ctx.conn.socket.fd);
        ctx.self.allocator.destroy(ctx.conn);
        ctx.self.allocator.destroy(ctx);
        return .disarm;
    }
};
