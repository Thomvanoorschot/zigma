const std = @import("std");

pub const OHLCUpdate = struct {
    arena_state: std.heap.ArenaAllocator,
    symbol: []const u8,
    open: f32,
    high: f32,
    low: f32,
    close: f32,
    trades: u64,
    volume: f32,
    interval: u64,
    timestamp: []const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, args: struct {
        symbol: []const u8,
        open: f32,
        high: f32,
        low: f32,
        close: f32,
        trades: u64,
        volume: f32,
        interval: u64,
        timestamp: []const u8,
    }) !*Self {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        var arena = arena_state.allocator();
        const self = try allocator.create(Self);

        const symbol = try arena.dupe(u8, args.symbol);
        const timestamp = try arena_state.allocator().dupe(u8, args.timestamp);

        self.* = .{
            .arena_state = arena_state,
            .symbol = symbol,
            .open = args.open,
            .high = args.high,
            .low = args.low,
            .close = args.close,
            .trades = args.trades,
            .volume = args.volume,
            .interval = args.interval,
            .timestamp = timestamp,
        };
        return self;
    }

    pub fn deinit(self: Self) void {
        self.arena_state.deinit();
    }
};
