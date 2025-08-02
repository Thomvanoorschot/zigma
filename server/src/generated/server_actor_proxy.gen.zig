const std = @import("std");
const backstage = @import("backstage");
const Context = backstage.Context;
const MethodCall = backstage.MethodCall;
const zborParse = backstage.zborParse;
const zborStringify = backstage.zborStringify;
const zborDataItem = backstage.zborDataItem;
const ServerActor = @import("../http/server_actor.zig").ServerActor;
const cn_actr = @import("../http/connection_actor.zig");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const shared_models = @import("shared_models");
const ConnectionActor = cn_actr.ConnectionActor;
const ServerActorMessage = shared_models.ServerActor;
const Server = async_zocket.Server;
const ClientConnection = async_zocket.ClientConnection;
const ConnectionActorMessage = shared_models.ConnectionActor;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub const ServerActorProxy = struct {
    pub const is_proxy = true;
    ctx: *Context,
    allocator: std.mem.Allocator,
    underlying: *ServerActor,
    
    const Self = @This();

    pub const Method = enum(u32) {
        setup = 0,
        accept = 1,
    };

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        const underlying = try ServerActor.init(ctx, allocator);
        self.* = .{
            .ctx = ctx,
            .allocator = allocator,
            .underlying = underlying,
        };
        return self;
    }

    pub fn deinit(self: *Self) !void {
        try self.underlying.deinit();
        self.allocator.destroy(self);
    }
    inline fn methodWrapper0(self: *Self, params: []const u8) !void {
        const result = try zborParse(struct {
            host: []const u8,
            port: u32,
            max_connections: u32,
        }, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.setup(result.host, result.port, result.max_connections);
    }

    inline fn methodWrapper1(self: *Self, params: []const u8) !void {
        _ = params;
        return self.underlying.accept();
    }

    pub inline fn setup(self: *Self, host: []const u8, port: u32, max_connections: u32) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(.{.host = host, .port = port, .max_connections = max_connections}, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 0,
            .params = params_str.items,
        };
        return self.ctx.dispatchMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn accept(self: *Self) !void {
        const method_call = MethodCall{
            .method_id = 1,
            .params = "",
        };
        return self.ctx.dispatchMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn dispatchMethod(self: *Self, method_call: MethodCall) !void {
        return switch (method_call.method_id) {            0 => methodWrapper0(self, method_call.params),
            1 => methodWrapper1(self, method_call.params),
            else => error.UnknownMethod,
        };
    }
};
