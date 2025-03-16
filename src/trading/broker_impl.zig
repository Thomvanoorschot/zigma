const std = @import("std");
const krkn = @import("../kraken/broker.zig");
const alphazig = @import("alphazig");

const concurrency = alphazig.concurrency;
const Context = alphazig.Context;
const Coroutine = concurrency.Coroutine;

pub const BrokerType = enum {
    kraken,
};

pub const BrokerImpl = union(BrokerType) {
    kraken: *krkn.Broker,
    // Add more brokers as needed
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, broker_type: BrokerType) !Self {
        switch (broker_type) {
            .kraken => {
                return .{ .kraken = try krkn.Broker.init(allocator) };
            },
        }
    }

    pub fn deinit(self: *Self) void {
        switch (self.*) {
            inline else => |*broker| broker.deinit(),
        }
    }

    pub fn subscribeToOrderbook(self: *Self, ticker: []const u8) !void {
        switch (self.*) {
            inline else => |broker| return try broker.subscribeToOrderbook(ticker),
        }
    }

    pub fn readMessages(self: *Self) !void {
        switch (self.*) {
            inline else => |broker| return try broker.readMessages(),
        }
    }
};
