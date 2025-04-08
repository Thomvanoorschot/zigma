const std = @import("std");
const backstage = @import("backstage");
const shared_models = @import("shared_models");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Orderbook = shared_models.OrderBook;
const OrderbookMessage = @import("../trading/orderbook_actor.zig").OrderbookMessage;
const stringify = @import("zbor").stringify;
const parse = @import("zbor").parse;
const DataItem = @import("zbor").DataItem;
pub const ConnectionMessage = union(enum) {
    listen: ListenMessage,
    orderbook_update: *const Orderbook,
};

pub const InitMessage = struct {};
pub const ListenMessage = struct {};

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    socket: xev.TCP = undefined,
    read_completion: xev.Completion = undefined,
    write_completion: xev.Completion = undefined,
    close_context: *anyopaque = undefined,
    close_callback: *const fn (self: *anyopaque, conn: *Self) anyerror!void = undefined,
    close_completion: xev.Completion = undefined,
    io_buf: [8192]u8 = std.mem.zeroes([8192]u8),
    keep_alive: bool = false,
    write_buffers: std.ArrayList(std.ArrayList(u8)),
    write_completions: std.ArrayList(*xev.Completion),

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .write_completions = std.ArrayList(*xev.Completion).init(allocator),
            .write_buffers = std.ArrayList(std.ArrayList(u8)).init(allocator),
        };
        return self;
    }

    pub fn receive(self: *Self, message: *const Envelope(ConnectionMessage)) !void {
        switch (message.payload) {
            .listen => |_| {
                std.log.info("Received 'listen' message (already listening).", .{});
                // try self.server.listen();
            },
            .orderbook_update => |m| {
                var str = std.ArrayList(u8).init(self.allocator);
                self.write_buffers.append(str) catch unreachable;
                try stringify(m, .{
                    .ignore_override = true,
                    .field_settings = &.{
                        .{ .name = "allocator", .field_options = .{ .skip = .Skip } },
                    },
                }, str.writer());

                self.write(str);
            },
        }
    }

    pub fn read(self: *Self) void {
        self.socket.read(self.ctx.getLoop(), &self.read_completion, .{ .slice = &self.io_buf }, Self, self, readCallback);
    }
    fn readCallback(
        self_: ?*Self,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.TCP,
        buf: xev.ReadBuffer,
        result: xev.ReadError!usize,
    ) xev.CallbackAction {
        const self = self_ orelse unreachable;

        std.debug.print("Read callback\n", .{});
        const bytes_read = result catch |err| {
            std.log.err("Read error for fd={d}, closing connection: {any}", .{ self.socket.fd, err });
            self.close_callback(self.close_context, self) catch unreachable;
            return .disarm;
        };
        var it = std.mem.tokenizeAny(u8, buf.slice[0..bytes_read], "\r\n");

        while (it.next()) |line| {
            std.log.info("{s}", .{line});
            if (std.mem.eql(u8, line, "Connection: keep-alive")) {
                self.keep_alive = true;
            }
            if (std.mem.eql(u8, line, "start")) {
                // Temporary way of starting the sending
                std.debug.print("Starting to send data\n", .{});
                _ = self.ctx.send("orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
            }
        }
        if (bytes_read == 0) {
            std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
            self.close_callback(self.close_context, self) catch unreachable;
            return .disarm;
        }

        if (self.keep_alive) {
            return .rearm;
        }
        return .disarm;
    }

    pub fn write(self: *Self, buf: std.ArrayList(u8)) void {
        const new_completion = self.write_completions.allocator.create(xev.Completion) catch unreachable;
        self.write_completions.append(new_completion) catch unreachable;
        self.socket.write(self.ctx.getLoop(), new_completion, .{ .slice = buf.items }, Self, self, writeCallback);
    }
    fn writeCallback(
        self_: ?*Self,
        _: *xev.Loop,
        c: *xev.Completion,
        _: xev.TCP,
        _: xev.WriteBuffer,
        result: xev.WriteError!usize,
    ) xev.CallbackAction {
        const self = self_ orelse unreachable;
        for (self.write_completions.items, 0..) |item, idx| {
            if (item == c) {
                _ = self.write_completions.orderedRemove(idx);
                const wb = self.write_buffers.orderedRemove(idx);
                defer wb.deinit();
                break;
            }
        }
        defer self.write_completions.allocator.destroy(c);
        const bytes_written = result catch |err| {
            std.log.err("Write error to client: {any}. Closing connection.", .{err});
            self.close_callback(self.close_context, self) catch unreachable;
            return .disarm;
        };

        if (!self.keep_alive) {
            std.log.info("Wrote {d} bytes to client. Closing connection as requested.", .{bytes_written});
            self.close_callback(self.close_context, self) catch unreachable;
        }
        return .disarm;
    }
};
