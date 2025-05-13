const std = @import("std");

pub const OrderbookUpdate = struct {
    arena_state: std.heap.ArenaAllocator,
    symbol: []const u8,
    bids: [][2]f64,
    asks: [][2]f64,
    checksum: u64,
    timestamp: ?[]const u8 = null,

    const Self = @This();
    pub fn init(
        allocator: std.mem.Allocator,
        args: struct {
            symbol: []const u8,
            bids: []const [2]f64,
            asks: []const [2]f64,
            checksum: u64,
            timestamp: ?[]const u8 = null,
        },
    ) !*Self {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        const self = try allocator.create(Self);
        var arena = arena_state.allocator();
        const symbol = try arena.dupe(u8, args.symbol);

        var bids = try arena.alloc([2]f64, args.bids.len);
        for (args.bids, 0..) |bid, bid_idx| {
            bids[bid_idx] = .{ bid[0], bid[1] };
        }

        var asks = try arena.alloc([2]f64, args.asks.len);
        for (args.asks, 0..) |ask, ask_idx| {
            asks[ask_idx] = .{ ask[0], ask[1] };
        }
        const timestamp = if (args.timestamp) |ts| try arena.dupe(u8, ts) else null;

        self.* = .{
            .arena_state = arena_state,
            .symbol = symbol,
            .bids = bids,
            .asks = asks,
            .checksum = args.checksum,
            .timestamp = timestamp,
        };
        return self;
    }

    pub fn deinit(self: Self) void {
        self.arena_state.deinit();
    }
};
