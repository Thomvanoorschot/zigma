const std = @import("std");
const backstage = @import("backstage");
const svr = @import("server.zig");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Server = svr.Server;
const Connection = @import("connection.zig").Connection;
pub const ConnectionMessage = union(enum) {
    listen: ListenMessage,
};

pub const InitMessage = struct {};
pub const ListenMessage = struct {};

pub const ConnectionActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    connection: ?Connection = null,

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
        };
        return self;
    }

    pub fn receive(self: *Self, message: *const Envelope(ConnectionMessage)) !void {
        switch (message.payload) {
            .listen => |_| {
                std.log.info("Received 'listen' message (already listening).", .{});
                try self.server.listen();
            },
        }
    }
};
