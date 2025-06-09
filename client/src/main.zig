const std = @import("std");
const zignite = @import("zignite");
const App = @import("visualization/app.zig").App;
const shared_models = @import("shared_models");
const websocket = @import("wasm/websocket.zig");

const engine = zignite.engine;
const Orderbook = shared_models.Orderbook;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var shared_data = websocket.SharedData{
        .orderbooks = std.StringHashMap(*Orderbook).init(allocator),
    };
    // Create web worker
    const ww = try websocket.WebSocketWebWorker(websocket.SharedData).init(
        std.heap.c_allocator,
        "ws://127.0.0.1:8081",
        &shared_data,
        websocket.workerEntrypoint,
        .{
            .on_open_cb = websocket.onOpenCallback,
            .on_message_cb = websocket.onMessageCallback,
            .on_error_cb = websocket.onErrorCallback,
            .on_close_cb = websocket.onCloseCallback,
        },
    );
    defer std.heap.c_allocator.destroy(ww);

    // Main thread loop
    var e = try engine.Engine.init(.{
        .width = 1024,
        .height = 768,
    });
    defer e.deinit();
    const app = try App.init(allocator, &shared_data);
    defer app.deinit();

    while (e.startRender()) {
        defer e.endRender();
        try app.render();
    }
}
