const std = @import("std");
const backstage = @import("backstage");
const cn_actr = @import("connection_actor.zig");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const shared_models = @import("shared_models");

const ConnectionMessage = cn_actr.ConnectionMessage;
const ConnectionActor = cn_actr.ConnectionActor;
const ServerMessage = shared_models.ServerActor.message_union;
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Server = async_zocket.Server;
const ClientConnection = async_zocket.ClientConnection;
const ConnectionActorMessage = shared_models.ConnectionActor.message_union;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub const ServerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    server: Server = undefined,
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

    pub fn deinit(self: *Self) !void {
        try self.ctx.deinit();
    }

    pub fn receive(self: *Self, message: *const Envelope(ServerMessage)) !void {
        switch (message.payload) {
            .init => |m| {
                self.server = try Server.init(
                    self.allocator,
                    self.ctx.getLoop(),
                    .{
                        .host = m.host.Const,
                        .port = @intCast(m.port),
                        .max_connections = @intCast(m.max_connections),
                    },
                    self,
                    acceptCallback,
                );
            },
            .accept => |_| {
                self.server.accept();
            },
        }
    }

    fn acceptCallback(
        self_: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        client_conn: *ClientConnection,
    ) xev.CallbackAction {
        const self = unsafeAnyOpaqueCast(Self, self_);
        const fd_string = std.fmt.allocPrint(self.allocator, "{}", .{client_conn.socket.fd}) catch |err| {
            std.log.err("Failed to print fd: {any}", .{err});
            client_conn.close();
            return .rearm;
        };

        const connection_actor = ConnectionActor.init(self.allocator, client_conn) catch |err| {
            std.log.err("Failed to init connection actor: {any}", .{err});
            client_conn.close();
            return .rearm;
        };
        _ = self.ctx.attachChildActorImpl(
            ConnectionActor,
            ConnectionActorMessage,
            .{
                .id = fd_string,
            },
            connection_actor,
        ) catch |err| {
            std.log.err("Failed to attach connection actor: {any}", .{err});
            client_conn.close();
            return .rearm;
        };
        connection_actor.setup(self.ctx);

        return .rearm;
    }
};
