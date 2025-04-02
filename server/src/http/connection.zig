const std = @import("std");
const backstage = @import("backstage");

const xev = backstage.xev;

pub const Connection = struct {
    socket: xev.TCP,
    loop: *xev.Loop,
    read_completion: xev.Completion = undefined,
    write_completion: xev.Completion = undefined,
    close_context: *anyopaque,
    close_callback: *const fn (self: *anyopaque, conn: *Self) anyerror!void,
    close_completion: xev.Completion = undefined,
    io_buf: [8192]u8 = std.mem.zeroes([8192]u8),
    keep_alive: bool = false,
    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        socket: xev.TCP,
        loop: *xev.Loop,
        close_context: *anyopaque,
        comptime close_callback: *const fn (self: *anyopaque, conn: *Self) anyerror!void,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .socket = socket,
            .loop = loop,
            .close_context = close_context,
            .close_callback = close_callback,
        };
        return self;
    }

    pub fn read(self: *Self) void {
        self.socket.read(self.loop, &self.read_completion, .{ .slice = &self.io_buf }, Self, self, readCallback);
    }
    fn readCallback(
        self: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        buf: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const s = self orelse unreachable;

        std.debug.print("Read callback\n", .{});
        const bytes_read = result catch |err| {
            std.log.err("Read error for fd={d}, closing connection: {any}", .{ s.socket.fd, err });
            s.close_callback(s.close_context, s) catch unreachable;
            return .disarm;
        };
        var it = std.mem.tokenizeAny(u8, buf.slice[0..bytes_read], "\r\n");

        while (it.next()) |line| {
            std.log.info("{s}", .{line});
            if (std.mem.eql(u8, line, "Connection: keep-alive")) {
                s.keep_alive = true;
            }
        }
        if (bytes_read == 0) {
            std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
            s.close_callback(s.close_context, s) catch unreachable;
            return .disarm;
        }

        std.log.info("Read {d} bytes from client.", .{bytes_read});
        const response = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello World!";
        s.write(response);

        if (s.keep_alive) {
            return .rearm;
        } else {
            return .disarm;
        }

        return .disarm;
    }

    pub fn write(self: *Self, buf: []const u8) void {
        self.socket.write(self.loop, &self.write_completion, .{ .slice = buf }, Self, self, writeCallback);
    }
    fn writeCallback(
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
            s.close_callback(s.close_context, s) catch unreachable;
            return .disarm;
        };

        if (!s.keep_alive) {
            std.log.info("Wrote {d} bytes to client. Closing connection as requested.", .{bytes_written});
            s.close_callback(s.close_context, s) catch unreachable;
        }
        return .disarm;
    }
};
