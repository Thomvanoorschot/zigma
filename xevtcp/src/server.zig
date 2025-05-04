const std = @import("std");
const xev = @import("xev");
const clnt_conn = @import("client_connection.zig");

const Allocator = std.mem.Allocator;
const Loop = xev.Loop;
const TCP = xev.TCP;
const Completion = xev.Completion;
const ClientConnection = clnt_conn.ClientConnection;

pub const ServerOptions = struct {
    address: std.net.Address,
    max_connections: u31 = 1024,
};

pub const Server = struct {
    allocator: Allocator,
    loop: *Loop,
    options: ServerOptions,
    listen_socket: TCP,
    accept_completion: Completion = undefined,
    connections: std.ArrayList(*ClientConnection),

    cb_context: *anyopaque,
    accept_cb: *const fn (
        self_: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        client_conn: *ClientConnection,
    ) xev.CallbackAction,

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        loop: *Loop,
        options: ServerOptions,
        cb_context: *anyopaque,
        accept_cb: *const fn (
            self_: ?*anyopaque,
            _: *xev.Loop,
            _: *xev.Completion,
            client_conn: *ClientConnection,
        ) xev.CallbackAction,
    ) !Self {
        var self = Self{
            .allocator = allocator,
            .loop = loop,
            .options = options,
            .listen_socket = try TCP.init(options.address),
            .connections = std.ArrayList(*ClientConnection).init(allocator),
            .cb_context = cb_context,
            .accept_cb = accept_cb,
        };
        errdefer self.deinit();

        try self.listen_socket.bind(options.address);
        try self.listen_socket.listen(options.max_connections);
        
        return self;
    }

    pub fn deinit(_: *Self) void {
        // self.listen_socket.close();
        // self.accept_completion.cancel(self.loop);

        // while (self.connections.popOrNull()) |client_conn| {
        //     self.closeClientResources(client_conn);
        // }
        // self.connections.deinit();
    }

    pub fn startAccepting(self: *Self) void {
        self.listen_socket.accept(
            self.loop,
            &self.accept_completion,
            Self,
            self,
            internalAcceptCallback,
        );
    }

    fn internalAcceptCallback(
        self_: ?*Self,
        _: *Loop,
        _: *Completion,
        result: xev.AcceptError!TCP,
    ) xev.CallbackAction {
        const self = self_ orelse unreachable;

        const client_socket = result catch |err| {
            std.log.err("Failed to accept connection: {s}", .{@errorName(err)});
            return .rearm; // Keep listening
        };

        if (self.connections.items.len >= self.options.max_connections) {
            std.log.warn("Max connections ({d}) reached, rejecting new connection from fd {d}", .{ self.options.max_connections, client_socket.fd });
            // TODO Maybe close the socket?
            // client_socket.close();
            return .rearm; // Keep listening
        }

        const client_conn = ClientConnection.init(
            self.allocator,
            self,
            client_socket,
        ) catch |err| {
            std.log.err("Failed to allocate memory for client connection: {s}", .{@errorName(err)});
            // client_socket.close();
            return .rearm; // Keep listening
        };

        return self.accept_cb(
            self.cb_context,
            self.loop,
            &self.accept_completion,
            client_conn,
        );
    }

    fn closeClientConnection(self: *Self, client_conn: *ClientConnection) void {
        std.log.info("Closing connection fd={d}", .{client_conn.socket.fd});

        // Find and remove the client from the list
        for (self.connections.items, 0..) |conn, i| {
            if (conn == client_conn) {
                _ = self.connections.orderedRemove(i);
                break;
            }
        }

        client_conn.close();
    }
};
