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
    socket: xev.TCP,
    connections: std.ArrayList(*Connection),
    loop: *Loop,
    accept_completion: xev.Completion = undefined,
    close_completion: xev.Completion = undefined,
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, loop: *Loop, options: Options) !Self {
        const self = Self{
            .socket = try xev.TCP.init(options.address),
            .connections = try std.ArrayList(*Connection).initCapacity(
                allocator,
                options.max_connections,
            ),
            .loop = loop,
        };
        try self.socket.bind(options.address);
        try self.socket.listen(1);
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
        loop: *xev.Loop,
        _: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        // This is a socket per connection -- DO NOT FORGET
        const socket: xev.TCP = result catch {
            return .rearm;
        };

        if (self.?.connections.items.len >= self.?.connections.capacity) {
            std.log.warn("Connection limit reached ({d}), rejecting new connection", .{self.?.connections.capacity});
            var temp_close_completion: xev.Completion = undefined;
            socket.close(loop, &temp_close_completion, Self, self, closeCallback);
            return .rearm;
        }

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
        self.?.connections.append(conn) catch |err| {
            std.log.err("Failed to append connection to list: {any}", .{err});
            self.?.connections.allocator.destroy(conn);
            var temp_close_completion: xev.Completion = undefined;
            socket.close(loop, &temp_close_completion, Self, self, closeCallback);
            return .rearm;
        };
        conn.read();
        return .rearm;
    }

    fn closeConnection(self_: *anyopaque, conn: *Connection) void {
        const self: *Self = @ptrCast(@alignCast(self_));

        self.connections.allocator.destroy(conn);
        // TODO This is wrong and also obfuscates an issue where it crashes if there are no more allowed connections, need to fix first
        // _ = self.connections.pop();
        self.socket.close(self.loop, &self.close_completion, Self, self, closeCallback);
    }

    fn closeCallback(
        self: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        result: xev.CloseError!void,
    ) xev.CallbackAction {
        _ = self orelse unreachable;

        if (result) |_| {
            std.log.info("Client connection closed successfully.", .{});
        } else |err| {
            std.log.err("Error closing client connection: {any}", .{err});
        }

        std.log.info("Server ready for next connection.", .{});

        return .disarm;
    }
};
