const std = @import("std");
const backstage = @import("backstage");
const Context = backstage.Context;
const MethodCall = backstage.MethodCall;
const zborParse = backstage.zborParse;
const zborStringify = backstage.zborStringify;
const zborDataItem = backstage.zborDataItem;
const ServerActor = @import("../http/server_actor.zig").ServerActor;
const async_zocket = @import("async_zocket");
const type_utils = @import("../utils/type_utils.zig");
const Orderbook = @import("../trading/types/orderbook.zig").Orderbook;
const OHLCList = @import("../trading/types/ohlc_list.zig").OHLCList;
const shared_models = @import("shared_models");
const Server = async_zocket.Server;
const ClientConnection = async_zocket.ClientConnection;
const ClientMessage = shared_models.ClientMessage;
const ServerMessage = shared_models.ServerMessage;
const unsafeAnyOpaqueCast = type_utils.unsafeAnyOpaqueCast;
const ProtobufOrderbook = shared_models.Orderbook;
const ProtobufOrderbookLevel = shared_models.OrderbookLevel;
const ManagedString = shared_models.ManagedString;

pub const ServerActorProxy = struct {
    pub const is_proxy = true;
    ctx: *Context,
    allocator: std.mem.Allocator,
    underlying: *ServerActor,
    
    const Self = @This();

    pub const Method = enum(u32) {
        setup = 0,
        accept = 1,
        subscribeConnection = 2,
        unsubscribeConnection = 3,
        orderbookUpdated = 4,
        ohlcUpdated = 5,
        removeConnection = 6,
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
            port: u16,
            max_connections: u31,
        }, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.setup(result.host, result.port, result.max_connections);
    }

    inline fn methodWrapper1(self: *Self, params: []const u8) !void {
        _ = params;
        return self.underlying.accept();
    }

    inline fn methodWrapper2(self: *Self, params: []const u8) !void {
        const result = try zborParse(struct {
            connection_id: []const u8,
            ticker: []const u8,
            subscription_type: shared_models.SubscriptionType,
        }, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.subscribeConnection(result.connection_id, result.ticker, result.subscription_type);
    }

    inline fn methodWrapper3(self: *Self, params: []const u8) !void {
        const result = try zborParse(struct {
            connection_id: []const u8,
            ticker: []const u8,
            subscription_type: shared_models.SubscriptionType,
        }, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.unsubscribeConnection(result.connection_id, result.ticker, result.subscription_type);
    }

    inline fn methodWrapper4(self: *Self, params: []const u8) !void {
        const result = try zborParse(Orderbook, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.orderbookUpdated(result);
    }

    inline fn methodWrapper5(self: *Self, params: []const u8) !void {
        const result = try zborParse(OHLCList, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.ohlcUpdated(result);
    }

    inline fn methodWrapper6(self: *Self, params: []const u8) !void {
        const result = try zborParse([]const u8, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.removeConnection(result);
    }

    pub inline fn setup(self: *Self, host: []const u8, port: u16, max_connections: u31) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(.{.host = host, .port = port, .max_connections = max_connections}, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 0,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn accept(self: *Self) !void {
        const method_call = MethodCall{
            .method_id = 1,
            .params = "",
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn subscribeConnection(self: *Self, connection_id: []const u8, ticker: []const u8, subscription_type: shared_models.SubscriptionType) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(.{.connection_id = connection_id, .ticker = ticker, .subscription_type = subscription_type}, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 2,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn unsubscribeConnection(self: *Self, connection_id: []const u8, ticker: []const u8, subscription_type: shared_models.SubscriptionType) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(.{.connection_id = connection_id, .ticker = ticker, .subscription_type = subscription_type}, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 3,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn orderbookUpdated(self: *Self, orderbook: Orderbook) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(orderbook, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 4,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn ohlcUpdated(self: *Self, ohlc: OHLCList) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(ohlc, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 5,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn removeConnection(self: *Self, connection_id: []const u8) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(connection_id, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 6,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn enqueueMethodCall(self: *Self, method_call: MethodCall) !void {
        return switch (method_call.method_id) {            0 => methodWrapper0(self, method_call.params),
            1 => methodWrapper1(self, method_call.params),
            2 => methodWrapper2(self, method_call.params),
            3 => methodWrapper3(self, method_call.params),
            4 => methodWrapper4(self, method_call.params),
            5 => methodWrapper5(self, method_call.params),
            6 => methodWrapper6(self, method_call.params),
            else => error.UnknownMethod,
        };
    }
};
