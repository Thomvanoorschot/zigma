const std = @import("std");
const wdw = @import("window.zig");

const Window = wdw.Window;

pub fn WindowGroup(comptime I: type) type {
    return struct {
        windows: std.ArrayList(*Window(I)),
        next_window_offset: u32 = 0,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
        ) !*Self {
            const self = try allocator.create(Self);
            self.* = .{
                .windows = std.ArrayList(*Window(I)).init(allocator),
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.windows.deinit();
        }

        pub fn openWindow(self: *Self, impl: I) !void {
            const offset: f32 = @floatFromInt(self.next_window_offset * 30);
            const initial_x: f32 = 50.0 + offset;
            const initial_y: f32 = 100.0 + offset;
            const window = try Window(I).init(self.windows.allocator, impl, .{
                .initial_pos = .{ .x = initial_x, .y = initial_y },
            });
            try self.windows.append(window);
            self.next_window_offset += 1;
        }
    };
}
