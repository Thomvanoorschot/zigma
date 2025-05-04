const std = @import("std");
const xev = @import("xev");
const svr = @import("server.zig");

const TCP = xev.TCP;
const Completion = xev.Completion;
const Loop = xev.Loop;
const Server = svr.Server;
pub const ClientConnection = struct {
    allocator: std.mem.Allocator,
    server: *Server,
    socket: TCP,
    read_buffer: [1024]u8 = undefined,
    read_completion: Completion = undefined,
    write_completions: std.ArrayList(*Completion),
    keep_alive: bool = false,
    is_closing: bool = false,

    close_context: *anyopaque = undefined,
    close_cb: ?*const fn (
        self_: ?*anyopaque,
    ) anyerror!void = null,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        server: *Server,
        socket: TCP,
    ) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .allocator = allocator,
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
            self_: ?*anyopaque,
            payload: []const u8,
        ) void,
    ) void {
        const read_userdata = struct {
            self: *Self,
            cb_context: *anyopaque,
        };
        const internal_callback = struct {
            fn inner(
                ud: ?*read_userdata,
                _: *Loop,
                _: *Completion,
                _: TCP,
                buf: xev.ReadBuffer,
                r: xev.ReadError!usize,
            ) xev.CallbackAction {
                const userdata = ud orelse unreachable;
                const inner_self = userdata.self;
                const inner_cb_context = userdata.cb_context;
                if (inner_self.is_closing) {
                    inner_self.allocator.destroy(userdata);
                    return .disarm;
                }
                const bytes_read = r catch |err| {
                    if (err == error.ConnectionResetByPeer) {
                        inner_self.is_closing = true;
                        inner_self.close();
                        return .disarm;
                    }
                    std.log.err("Read error for fd={d}, closing connection: {any}", .{ inner_self.socket.fd, err });
                    return .disarm;
                };
                var it = std.mem.tokenizeAny(u8, buf.slice[0..bytes_read], "\r\n");

                // TODO: Only for initial message?
                while (it.next()) |line| {
                    if (std.mem.eql(u8, line, "Connection: keep-alive")) {
                        inner_self.keep_alive = true;
                    }
                }
                if (bytes_read == 0) {
                    std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
                    inner_self.is_closing = true;
                    inner_self.close();
                    return .disarm;
                }

                // TODO: Proably make it return something optionally
                read_cb(inner_cb_context, buf.slice[0..bytes_read]);
                if (inner_self.keep_alive) {
                    return .rearm;
                }
                return .disarm;
            }
        }.inner;
        const rud = self.allocator.create(read_userdata) catch unreachable;
        rud.* = .{ .self = self, .cb_context = cb_context };
        self.socket.read(
            self.server.loop,
            &self.read_completion,
            .{ .slice = &self.read_buffer },
            read_userdata,
            rud,
            internal_callback,
        );
    }

    pub fn write(self: *Self, data: []const u8) void {
        const new_completion = self.write_completions.allocator.create(Completion) catch unreachable;
        self.write_completions.append(new_completion) catch unreachable;
        self.socket.write(
            self.server.loop,
            new_completion,
            .{ .slice = data },
            Self,
            self,
            internalWriteCallback,
        );
    }

    fn internalWriteCallback(
        self_: ?*Self,
        _: *Loop,
        c: *Completion,
        _: TCP,
        _: xev.WriteBuffer,
        r: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_ orelse unreachable;
        if (self.is_closing) {
            std.debug.print("Write callback: is_closing\n", .{});
            return .disarm;
        }
        for (self.write_completions.items, 0..) |item, idx| {
            if (item == c) {
                _ = self.write_completions.orderedRemove(idx);
                break;
            }
        }
        defer self.write_completions.allocator.destroy(c);
        const bytes_written = r catch |err| {
            std.log.err("Write error to client: {any}. Closing connection.", .{err});
            self.close();
            return .disarm;
        };

        if (!self.keep_alive) {
            std.log.info("Wrote {d} bytes to client. Closing connection as requested.", .{bytes_written});
            self.close();
        }
        return .disarm;
    }
    pub fn setCloseCallback(
        self: *Self,
        close_context: *anyopaque,
        cb: *const fn (
            self_: ?*anyopaque,
        ) anyerror!void,
    ) void {
        self.close_context = close_context;
        self.close_cb = cb;
    }
    fn close(self: *Self) void {
        self.is_closing = true;
        if (self.close_cb) |cb| {
            cb(self.close_context) catch |close_err| {
                std.log.err("Failed to close connection: {any}", .{close_err});
            };
        }
    }
};
