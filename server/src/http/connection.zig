const std = @import("std");
const backstage = @import("backstage");

const xev = backstage.xev;

pub const Connection = struct {
    socket: xev.TCP,
    loop: *xev.Loop,
    completion: xev.Completion = undefined,
    close_context: *anyopaque,
    close_callback: *const fn (self: *anyopaque, conn: *Self) void,
    io_buf: [8192]u8 = std.mem.zeroes([8192]u8),

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        socket: xev.TCP,
        loop: *xev.Loop,
        close_context: *anyopaque,
        comptime close_callback: *const fn (self: *anyopaque, conn: *Self) void,
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
        self.socket.read(self.loop, &self.completion, .{ .slice = &self.io_buf }, Self, self, readCallback);
    }
    fn readCallback(
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
            s.close_callback(s.close_context, s);
            return .disarm;
        };

        if (bytes_read == 0) {
            std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
            s.close_callback(s.close_context, s);
            return .disarm;
        }

        std.log.info("Read {d} bytes from client.", .{bytes_read});
        const response = "HTTP/1.1 200 OK\r\nContent-Length: 12\r\n\r\nHello World!";
        s.write(response);

        return .disarm;
    }

    pub fn write(self: *Self, buf: []const u8) void {
        self.socket.write(self.loop, &self.completion, .{ .slice = buf }, Self, self, writeCallback);
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
            s.close_callback(s.close_context, s);
            return .disarm;
        };

        std.log.info("Wrote {d} bytes to client. Closing connection as requested.", .{bytes_written});
        s.close_callback(s.close_context, s);
        return .disarm;
    }
};
