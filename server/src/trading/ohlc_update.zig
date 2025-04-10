const std = @import("std");

pub const OHLCUpdate = struct {
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


pub const UpdateData = struct {
    symbol: []const u8,
    open: f32,
    high: f32,
    low: f32,
    close: f32,
    trades: u64,
    volume: f32,
    interval: u64,
    timestamp: []const u8,
};
