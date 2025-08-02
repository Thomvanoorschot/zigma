const std = @import("std");
const backstage = @import("backstage");
const Context = backstage.Context;
const MethodCall = backstage.MethodCall;
const zborParse = backstage.zborParse;
const zborStringify = backstage.zborStringify;
const zborDataItem = backstage.zborDataItem;
const ConnectionActor = @import("../http/connection_actor.zig").ConnectionActor;
const shared_models = @import("shared_models");
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const Orderbook = shared_models.Orderbook;
const ServerMessage = shared_models.ServerMessage;
const ConnectionActorMessage = shared_models.ConnectionActor;
const ClientMessage = shared_models.ClientMessage;
const OrderbookActorMessage = shared_models.OrderbookActor;
const OHLCActorMessage = shared_models.OHLCActor;
const ClientConnection = async_zocket.ClientConnection;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;

pub const ConnectionActorProxy = struct {
    pub const is_proxy = true;
    ctx: *Context,
    allocator: std.mem.Allocator,
    underlying: *ConnectionActor,
    
    const Self = @This();

    pub const Method = enum(u32) {
        setup = 0,
        orderbookUpdated = 1,
        ohlcUpdated = 2,
        write = 3,
    };

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        const underlying = try ConnectionActor.init(ctx, allocator);
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
        const result = try zborParse(* ClientConnection, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.setup(result);
    }

    inline fn methodWrapper1(self: *Self, params: []const u8) !void {
        const result = try zborParse(Orderbook, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.orderbookUpdated(result);
    }

    inline fn methodWrapper2(self: *Self, params: []const u8) !void {
        const result = try zborParse(OHLCActorMessage, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.ohlcUpdated(result);
    }

    inline fn methodWrapper3(self: *Self, params: []const u8) !void {
        const result = try zborParse([]const u8, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.write(result);
    }

    pub inline fn setup(self: *Self, client_conn: * ClientConnection) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(client_conn, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 0,
            .params = params_str.items,
        };
        return self.ctx.dispatchMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn orderbookUpdated(self: *Self, orderbook: Orderbook) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(orderbook, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 1,
            .params = params_str.items,
        };
        return self.ctx.dispatchMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn ohlcUpdated(self: *Self, ohlc: OHLCActorMessage) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(ohlc, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 2,
            .params = params_str.items,
        };
        return self.ctx.dispatchMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn write(self: *Self, buf: []const u8) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(buf, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 3,
            .params = params_str.items,
        };
        return self.ctx.dispatchMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn dispatchMethod(self: *Self, method_call: MethodCall) !void {
        return switch (method_call.method_id) {            0 => methodWrapper0(self, method_call.params),
            1 => methodWrapper1(self, method_call.params),
            2 => methodWrapper2(self, method_call.params),
            3 => methodWrapper3(self, method_call.params),
            else => error.UnknownMethod,
        };
    }
};
