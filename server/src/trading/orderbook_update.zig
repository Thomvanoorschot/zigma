const std = @import("std");

pub const OrderbookUpdate = struct {
    arena_state: std.heap.ArenaAllocator,
    data: *UpdateData,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) !Self {
        var arena_state = std.heap.ArenaAllocator.init(allocator);
        return Self{
            .arena_state = arena_state,
            .data = try arena_state.allocator().create(UpdateData),
        };
    }

    pub fn deinit(self: Self) void {
        self.arena_state.deinit();
    }
};

pub const PriceLevel = struct {
    price: f64,
    qty: f64,
};

pub const UpdateData = struct {
    symbol: []const u8,
    bids: [][2]f64,
    asks: [][2]f64,
    checksum: u64,
    timestamp: ?[]const u8 = null,
};
