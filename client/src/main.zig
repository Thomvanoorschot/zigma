const std = @import("std");
const xev = @import("xev");
const Loop = xev.Loop;
const App = @import("visualization/app.zig").App;
const window_title = "zigma_client";

pub fn main() !void {
    var loop = try Loop.init(.{});
    defer loop.deinit();
    var allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = allocator_state.allocator();

    var app = try App.init(
        allocator,
        &loop,
        window_title,
        1920,
        1080,
    );
    app.start();


    try loop.run(.until_done);
}
