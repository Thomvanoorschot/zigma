const std = @import("std");
const backstage = @import("backstage");
const cn_actr = @import("connection_actor.zig");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const shared_models = @import("shared_models");

const ConnectionActor = cn_actr.ConnectionActor;
const ServerActorMessage = shared_models.ServerActor;
const xev = backstage.xev;
const Context = backstage.Context;
const Envelope = backstage.Envelope;
const ActorInterface = backstage.ActorInterface;
const Server = async_zocket.Server;
const ClientConnection = async_zocket.ClientConnection;
const ConnectionActorMessage = shared_models.ConnectionActor.message_union;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

// @generate-proxy
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

    pub fn deinit(_: *Self) !void {}

    pub fn setup(self: *Self, host: []const u8, port: u32, max_connections: u32) !void {
        self.server = try Server.init(
            self.allocator,
            self.ctx.getLoop(),
            .{
                .host = host,
                .port = port,
                .max_connections = max_connections,
                .use_tls = true,
                .cert_file = "server.crt",
                .key_file = "server.key",
            },
            self,
            acceptCallback,
        );
    }

    pub fn accept(self: *Self) !void {
        self.server.accept();
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

        const connection_actor = self.ctx.spawnChildActor(ConnectionActor, .{
            .id = fd_string,
        }) catch |err| {
            std.log.err("Failed to spawn connection actor: {any}", .{err});
            client_conn.close();
            return .rearm;
        };

        connection_actor.setup(client_conn);

        return .rearm;
    }
};
