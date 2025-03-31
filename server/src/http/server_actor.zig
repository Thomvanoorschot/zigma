const std = @import("std");
const backstage = @import("backstage");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;

pub const ServerMessage = union(enum) {
    listen: ServerListenRequest,
};

pub const ServerListenRequest = struct {};

pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    listener: xev.TCP,
    accept_completion: xev.Completion = undefined,

    client_stream: ?xev.TCP = null,
    client_read_completion: xev.Completion = undefined,
    client_write_completion: xev.Completion = undefined,
    client_close_completion: xev.Completion = undefined,

    io_buf: [8192]u8 = std.mem.zeroes([8192]u8),

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const addr = try std.net.Address.parseIp4("127.0.0.1", 8081);
        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .listener = try xev.TCP.init(addr),
        };
        try self.listener.bind(addr);
        try self.listener.listen(10);

        self.start_accept();

        return self;
    }

    fn start_accept(self: *Self) void {
        self.listener.accept(&self.ctx.engine.loop, &self.accept_completion, Self, self, accept_callback);
    }

    fn accept_callback(
        self: ?*Self,
        loop: *xev.Loop,
        _: *xev.Completion,
        result: xev.AcceptError!xev.TCP,
    ) xev.CallbackAction {
        const s = self orelse unreachable;

        const client = result catch |err| {
            std.log.err("Failed to accept connection: {any}", .{err});
            return .rearm;
        };

        if (s.client_stream != null) {
            std.log.warn("Server busy, rejecting new connection", .{});
            var temp_close_completion: xev.Completion = undefined;
            client.close(loop, &temp_close_completion, void, null, close_rejected_callback);
            return .rearm;
        }

        std.log.info("Accepted new connection", .{});
        s.client_stream = client;

        s.start_read();

        return .rearm;
    }

    fn close_rejected_callback(
        _: ?*void,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        res: xev.CloseError!void,
    ) xev.CallbackAction {
        if (res) |_| {} else |err| {
            std.log.err("Error closing rejected connection: {any}", .{err});
        }
        return .disarm;
    }

    fn start_read(self: *Self) void {
        if (self.client_stream) |client| {
            std.log.debug("Starting read on client stream", .{});
            client.read(&self.ctx.engine.loop, &self.client_read_completion, .{ .slice = &self.io_buf }, Self, self, read_callback);
        } else {
            std.log.warn("start_read called with no active client stream", .{});
        }
    }

    fn read_callback(
        self: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        _: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const s = self orelse unreachable;

        const bytes_read = result catch |err| {
            std.log.err("Read error from client: {any}. Closing connection.", .{err});
            s.start_close();
            return .disarm;
        };

        if (bytes_read == 0) {
            std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
            s.start_close();
            return .disarm;
        }

        std.log.info("Read {d} bytes from client.", .{bytes_read});
        const response = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello World!";
        s.start_write(response);

        return .disarm;
    }

    fn start_write(self: *Self, data: []const u8) void {
        if (self.client_stream) |client| {
            std.log.debug("Starting write to client stream", .{});
            client.write(&self.ctx.engine.loop, &self.client_write_completion, .{ .slice = data }, Self, self, write_callback);
        } else {
            std.log.warn("start_write called with no active client stream", .{});
        }
    }

    fn write_callback(
        self: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        _: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        const s = self orelse unreachable;

        const bytes_written = result catch |err| {
            std.log.err("Write error to client: {any}. Closing connection.", .{err});
            s.start_close();
            return .disarm;
        };

        std.log.info("Wrote {d} bytes to client. Closing connection as requested.", .{bytes_written});
        s.start_close();

        return .disarm;
    }

    fn start_close(self: *Self) void {
        if (self.client_stream) |client| {
            std.log.debug("Starting close on client stream", .{});
            client.close(&self.ctx.engine.loop, &self.client_close_completion, Self, self, close_callback);
        } else {
            std.log.warn("start_close called with no active client stream", .{});
        }
    }

    fn close_callback(
        self: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        result: xev.CloseError!void,
    ) xev.CallbackAction {
        const s = self orelse unreachable;

        if (result) |_| {
            std.log.info("Client connection closed successfully.", .{});
        } else |err| {
            std.log.err("Error closing client connection: {any}", .{err});
        }

        s.client_stream = null;
        s.client_read_completion = undefined;
        s.client_write_completion = undefined;
        s.client_close_completion = undefined;

        std.log.info("Server ready for next connection.", .{});

        return .disarm;
    }

    pub fn deinit(self: *Self) void {
        // Import only posix for closing
        const posix = std.posix;

        // Synchronously close the client stream's FD if it exists
        if (self.client_stream) |client| {
            posix.close(client.fd);
            // Ensure we mark it as null after attempting close
            self.client_stream = null;
        }

        // Synchronously close the listener stream's FD
        posix.close(self.listener.fd);
        // Destroy the actor's memory
        self.allocator.destroy(self);
    }

    pub fn receive(_: *Self, message: *const Envelope(ServerMessage)) !void {
        switch (message.payload) {
            .listen => |_| {
                std.log.info("Received 'listen' message (already listening).", .{});
            },
        }
    }
};
