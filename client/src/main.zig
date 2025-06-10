const std = @import("std");
const zignite = @import("zignite");
const App = @import("visualization/app.zig").App;
const shared_models = @import("shared_models");
const sd = @import("wasm/shared_data.zig");

const SharedData = sd.SharedData;
const engine = zignite.engine;
const Orderbook = shared_models.Orderbook;
const WebsocketWebWorker = zignite.websocket_web_worker.WebSocketWebWorker;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var shared_data = SharedData{
        .orderbooks = std.StringHashMap(*Orderbook).init(allocator),
    };

    // Create engine
    var e = try engine.Engine.init(.{
        .width = 1024,
        .height = 768,
    });
    defer e.deinit();

    const app = try App.init(allocator, &shared_data);
    defer app.deinit();

    // Create web worker
    const ww = try WebsocketWebWorker.init(
        std.heap.c_allocator,
        "ws://127.0.0.1:8081",
        .{
            .callback_ctx = app,
            .on_open_cb = App.onWebsocketOpenCallback,
            .on_message_cb = App.onWebsocketMessageCallback,
            .on_error_cb = App.onWebsocketErrorCallback,
            .on_close_cb = App.onWebsocketCloseCallback,
        },
    );
    defer std.heap.c_allocator.destroy(ww);

    // Main thread loop
    while (e.startRender()) {
        defer e.endRender();
        try app.render();
    }
}
