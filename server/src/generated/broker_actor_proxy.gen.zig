const std = @import("std");
const backstage = @import("backstage");
const Context = backstage.Context;
const MethodCall = backstage.MethodCall;
const zborParse = backstage.zborParse;
const zborStringify = backstage.zborStringify;
const zborDataItem = backstage.zborDataItem;
const BrokerActor = @import("../trading/broker_actor.zig").BrokerActor;
const krkn = @import("../trading/exchanges/kraken/broker.zig");
const brkr_impl = @import("../trading/broker_impl.zig");
const orderbook_actor = @import("../trading/orderbook_actor.zig");
const ohlc_actor = @import("../trading/ohlc_actor.zig");
const unsafeAnyOpaqueCast = @import("../utils/type_utils.zig").unsafeAnyOpaqueCast;
const OrderbookUpdate = @import("../trading/types/orderbook_update.zig").OrderbookUpdate;
const OHLCUpdate = @import("../trading/types/ohlc_update.zig").OHLCUpdate;
const BrokerImpl = brkr_impl.BrokerImpl;
const BrokerPayload = brkr_impl.BrokerPayload;
const BrokerType = brkr_impl.BrokerType;
const MarketDataType = brkr_impl.MarketDataType;

pub const BrokerActorProxy = struct {
    pub const is_proxy = true;
    ctx: *Context,
    allocator: std.mem.Allocator,
    underlying: *BrokerActor,
    
    const Self = @This();

    pub const Method = enum(u32) {
        setup = 0,
        start = 1,
    };

    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        const underlying = try BrokerActor.init(ctx, allocator);
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
        const result = try zborParse(BrokerType, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.setup(result);
    }

    inline fn methodWrapper1(self: *Self, params: []const u8) !void {
        const result = try zborParse(struct {
            ticker: []const u8,
            market_data_type: MarketDataType,
        }, try zborDataItem.new(params), .{ .allocator = self.allocator });
        return self.underlying.start(result.ticker, result.market_data_type);
    }

    pub inline fn setup(self: *Self, broker_type: BrokerType) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(broker_type, .{
            .allocator = self.allocator,
            .array_serialization_type = .ArrayIndefinite,
        }, params_str.writer());
        const method_call = MethodCall{
            .method_id = 0,
            .params = params_str.items,
        };
        return self.ctx.enqueueMethodCall(self.ctx.actor_id, method_call);    }

    pub inline fn start(self: *Self, ticker: []const u8, market_data_type: MarketDataType) !void {
        var params_str = std.ArrayList(u8).init(self.allocator);
        defer params_str.deinit();
        try zborStringify(.{.ticker = ticker, .market_data_type = market_data_type}, .{}, params_str.writer());
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
