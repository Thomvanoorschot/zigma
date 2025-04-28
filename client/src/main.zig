const std = @import("std");
const xev = @import("xev");
const Loop = xev.Loop;
const App = @import("visualization/app.zig").App;
const window_title = "zigma_client";

pub fn main() !void {
    // var thread_pool = xev.ThreadPool.init(.{
    //     .max_threads = 0,
    // });
    // defer thread_pool.deinit();
    var loop = try Loop.init(.{
        // .thread_pool = &thread_pool,
    });
    defer loop.deinit();
    var allocator_state = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = allocator_state.allocator();

    var app = try App.init(
        allocator,
        &loop,
        window_title,
        3456,
        2234,
    );
    app.start();

    try loop.run(.until_done);
}
