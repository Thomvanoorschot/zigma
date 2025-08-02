const std = @import("std");
const backstage = @import("backstage");
const Context = backstage.Context;
const MethodCall = backstage.MethodCall;
const zborParse = backstage.zborParse;
const zborStringify = backstage.zborStringify;
const zborDataItem = backstage.zborDataItem;
const OHLCActor = @import("../trading/ohlc_actor.zig").OHLCActor;
const brkr_impl = @import("../trading/broker_impl.zig");
const brkr_actr = @import("../trading/broker_actor.zig");
const date_utils = @import("../utils/date_utils.zig");
const OHLCList = @import("../trading/types/ohlc_list.zig").OHLCList;
const OHLCUpdate = @import("../trading/types/ohlc_update.zig").OHLCUpdate;
const OHLC = @import("../trading/types/ohlc.zig").OHLC;
const BrokerType = brkr_impl.BrokerType;
const BrokerActor = brkr_actr.BrokerActor;

pub const OHLCActorProxy = struct {
    pub const is_proxy = true;
    ctx: *Context,
    allocator: std.mem.Allocator,
    underlying: *OHLCActor,
    
    const Self = @This();

    pub const Method = enum(u32) {
        start = 0,
        update = 1,
    };

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        const underlying = try OHLCActor.init(ctx, allocator);
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
        const result = try zborParse([]const u8, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.start(result);
    }

    inline fn methodWrapper1(self: *Self, params: []const u8) !void {
        const result = try zborParse(OHLCUpdate, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.update(result);
    }

    pub inline fn start(self: *Self, ticker: []const u8) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(ticker, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 0,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn update(self: *Self, u: OHLCUpdate) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(u, .{}, params_str.writer());
        const method_call = MethodCall{
            .method_id = 1,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn enqueueMethodCall(self: *Self, method_call: MethodCall) !void {
        return switch (method_call.method_id) {            0 => methodWrapper0(self, method_call.params),
            1 => methodWrapper1(self, method_call.params),
            else => error.UnknownMethod,
        };
    }
};
