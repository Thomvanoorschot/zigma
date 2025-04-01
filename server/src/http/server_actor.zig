const std = @import("std");
const backstage = @import("backstage");
const svr = @import("server.zig");

const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Server = svr.Server;

pub const ServerMessage = union(enum) {
    listen: ListenMessage,
};

pub const InitMessage = struct {};
pub const ListenMessage = struct {};

pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    server: Server,

    const Self = @This();

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .server = try Server.init(allocator, ctx.getLoop(), .{
                .address = try std.net.Address.parseIp4("127.0.0.1", 8081),
                .max_connections = 2,
            }),
        };
        return self;
    }

    pub fn receive(self: *Self, message: *const Envelope(ServerMessage)) !void {
        switch (message.payload) {
            .listen => |_| {
                std.log.info("Received 'listen' message (already listening).", .{});
                try self.server.listen();
            },
        }
    }
};
