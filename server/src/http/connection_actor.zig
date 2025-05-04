const std = @import("std");
const backstage = @import("backstage");
const shared_models = @import("shared_models");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Orderbook = shared_models.OrderBook;
const OHLCList = shared_models.OHLCList;
const stringifyOHLCList = shared_models.stringifyOHLCList;
const OrderbookMessage = @import("../trading/orderbook_actor.zig").OrderbookMessage;
const OHLCMessage = @import("../trading/ohlc_actor.zig").OHLCMessage;
const stringify = @import("zbor").stringify;
const parse = @import("zbor").parse;
const DataItem = @import("zbor").DataItem;
pub const ConnectionMessage = union(enum) {
    orderbook_update: *Orderbook,
    ohlc_update: OHLCList,
};

pub const InitMessage = struct {};

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    socket: xev.TCP = undefined,
    read_completion: xev.Completion = undefined,
    close_context: *anyopaque = undefined,
    close_callback: *const fn (self: *anyopaque, conn: *Self) anyerror!void = undefined,
    io_buf: [8192]u8 = std.mem.zeroes([8192]u8),
    keep_alive: bool = false,
    write_completions: std.ArrayList(*xev.Completion),
    is_closing: bool = false,

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .write_completions = std.ArrayList(*xev.Completion).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.write_completions.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(ConnectionMessage)) !void {
        if (self.is_closing) {
            return;
        }
        switch (message.payload) {
            .orderbook_update => |m| {
                const str = try m.stringify(self.allocator);
                self.write(str);
            },
            .ohlc_update => |m| {
                const str = try stringifyOHLCList(self.allocator, m);

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

        if (self.is_closing) {
            std.debug.print("Read callback: is_closing\n", .{});
            return .disarm;
        }
        const bytes_read = result catch |err| {
            if (err == error.ConnectionResetByPeer) {
                self.is_closing = true;
                self.close() catch |close_err| {
                    std.log.err("Failed to close connection: {any}", .{close_err});
                };
                return .disarm;
            }
            std.log.err("Read error for fd={d}, closing connection: {any}", .{ self.socket.fd, err });
            return .disarm;
        };
        var it = std.mem.tokenizeAny(u8, buf.slice[0..bytes_read], "\r\n");

        while (it.next()) |line| {
            if (std.mem.eql(u8, line, "Connection: keep-alive")) {
                self.keep_alive = true;
            }
            if (std.mem.eql(u8, line, "start")) {
                // Temporary way of starting the sending
                self.ctx.send("orderbook_actor", OrderbookMessage{ .subscribe = .{} }) catch unreachable;
                // _ = self.ctx.send("ohlc_actor", OHLCMessage{ .subscribe = .{} }) catch unreachable;
            }
        }
        if (bytes_read == 0) {
            std.log.info("Client sent 0 bytes (potentially closed). Closing connection.", .{});
            self.is_closing = true;
            self.close() catch |close_err| {
                std.log.err("Failed to close connection: {any}", .{close_err});
            };
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
        self.socket.write(
            self.ctx.getLoop(),
            new_completion,
            .{ .slice = buf.items },
            Self,
            self,
            writeCallback,
        );
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
        const bytes_written = result catch |err| {
            std.log.err("Write error to client: {any}. Closing connection.", .{err});
            self.close() catch |close_err| {
                std.log.err("Failed to close connection: {any}", .{close_err});
            };
            return .disarm;
        };

        if (!self.keep_alive) {
            std.log.info("Wrote {d} bytes to client. Closing connection as requested.", .{bytes_written});
            self.close() catch |close_err| {
                std.log.err("Failed to close connection: {any}", .{close_err});
            };
        }
        return .disarm;
    }
    pub fn close(self: *Self) !void {
        self.is_closing = true;
        try self.ctx.send("orderbook_actor", OrderbookMessage{
            .unsubscribe = .{},
        });
        try self.close_callback(self.close_context, self);
    }
};
