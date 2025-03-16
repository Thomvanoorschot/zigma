const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const alphazig = @import("alphazig");
const broker_impl = @import("broker_impl.zig");

const concurrency = alphazig.concurrency;
const Context = alphazig.Context;
const Coroutine = concurrency.Coroutine;
const BrokerImpl = broker_impl.BrokerImpl;
const BrokerType = broker_impl.BrokerType;
pub const BrokerMessage = union(enum) {
    init: BrokerInitRequest,
    subscribe: BrokerSubscribeRequest,
    request: BrokerRequest,
};

pub const BrokerInitRequest = struct {
    broker: BrokerType,
};

pub const BrokerSubscribeRequest = struct {
    ticker: []const u8,
};

pub const BrokerRequest = struct {};

pub const BrokerActor = struct {
    allocator: std.mem.Allocator,
    ctx: *Context,
    broker: ?BrokerImpl,

    const Self = @This();
    pub fn init(ctx: *Context, allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        self.* = .{
            .broker = undefined,
            .ctx = ctx,
            .allocator = allocator,
        };

        return self;
    }

    pub fn receive(self: *Self, message: *const BrokerMessage) !void {
        switch (message.*) {
            .init => |m| {
                self.broker = try BrokerImpl.init(self.allocator, m.broker);
            },
            .subscribe => |m| {
                try self.broker.?.subscribeToOrderbook(m.ticker);
            },
            .request => |_| {
                try self.broker.?.readMessages();
            },
        }
    }
};
