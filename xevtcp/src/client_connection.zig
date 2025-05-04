const std = @import("std");
const xev = @import("xev");
const svr = @import("server.zig");

const TCP = xev.TCP;
const Completion = xev.Completion;
const Loop = xev.Loop;
const Server = svr.Server;
pub const ClientConnection = struct {
    server: *Server,
    socket: TCP,
    read_buffer: [1024]u8 = undefined,
    read_completion: Completion = undefined,
    write_completions: std.ArrayList(*Completion),
    keep_alive: bool = false,
    is_closing: bool = false,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        server: *Server,
        socket: TCP,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .server = server,
            .socket = socket,
            .write_completions = std.ArrayList(*xev.Completion).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.write_completions.deinit();
    }
    pub fn read(
        self: *Self,
        cb_context: *anyopaque,
        comptime read_cb: *const fn (
            self_: ?*Self,
            payload: []const u8,
        ) void,
    ) void {
        const internal_callback = struct {
            fn inner(
                internal_self_: ?*Self,
                _: *Loop,
                _: *Completion,
                _: TCP,
                buf: xev.ReadBuffer,
                r: xev.ReadError!usize,
            ) xev.CallbackAction {
                const internal_self = internal_self_ orelse unreachable;

                if (internal_self.is_closing) {
                    return .disarm;
                }
                const bytes_read = r catch |err| {
                    if (err == error.ConnectionResetByPeer) {
                        internal_self.is_closing = true;
                        internal_self.close() catch |close_err| {
                            std.log.err("Failed to close connection: {any}", .{close_err});
                        };
                        return .disarm;
                    }
                    std.log.err("Read error for fd={d}, closing connection: {any}", .{ internal_self.socket.fd, err });
                    return .disarm;
                };
                var it = std.mem.tokenizeAny(u8, buf.slice[0..bytes_read], "\r\n");

                // TODO: Only for initial message?
                while (it.next()) |line| {
                    if (std.mem.eql(u8, line, "Connection: keep-alive")) {
                        internal_self.keep_alive = true;
                    }
                }
                if (bytes_read == 0) {
                    std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
                    internal_self.is_closing = true;
                    internal_self.close() catch |close_err| {
                        std.log.err("Failed to close connection: {any}", .{close_err});
                    };
                    return .disarm;
                }

                // TODO: Proably make it return something optionally
                read_cb(cb_context, buf.slice[0..bytes_read]);
                if (internal_self.keep_alive) {
                    return .rearm;
                }
                return .disarm;
            }
        }.inner;
        self.socket.read(
            self.server.loop,
            &self.read_completion,
            .{ .slice = &self.read_buffer },
            Self,
            self,
            internal_callback,
        );
    }

    pub fn write(self: *Self, data: []const u8) void {
        const completion = self.server.loop.createCompletion();
        self.write_completions.append(completion) catch unreachable;
        self.socket.write(
            self.server.loop,
            completion,
            .{ .slice = data },
            Self,
            self,
            internalWriteCallback,
        );
    }

    fn internalWriteCallback(
        self_: ?*Self,
        _: *Loop,
        _: *Completion,
        _: TCP,
        _: xev.WriteBuffer,
        r: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_ orelse unreachable;

        // Send messages back to the client
        _ = r catch |err| {
            std.log.err("Write error to client {d}: {s}", .{ self.socket.fd, @errorName(err) });
            // Don't close immediately on write error, maybe transient?
            // Consider adding logic to close if write errors persist.
            return .disarm;
        };

        std.log.debug("Echoed data to client {d}", .{self.socket.fd});
        return .disarm; // Writes are not persistent
    }
};
