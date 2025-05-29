const std = @import("std");
const zignite = @import("zignite");
const ob = @import("visualization/orderbook.zig");
const shared_models = @import("shared_models");

const pthread = zignite.pthread;
const websocket = zignite.websocket;
const emscripten_utils = zignite.emscripten_utils;
const imgui = zignite.imgui;
const engine = zignite.engine;
const websocket_web_worker = zignite.websocket_web_worker;
const WebSocketWebWorker = websocket_web_worker.WebSocketWebWorker;

const parseOrderbook = shared_models.parseOrderbook;
const OrderbookWindows = ob.OrderbookWindows;
const SharedData = struct {
    orderbook_windows: *OrderbookWindows,
};

fn workerEntrypoint(web_worker: *WebSocketWebWorker(SharedData)) !void {
    _ = web_worker;
}

fn onOpenCallback(web_worker: *WebSocketWebWorker(SharedData)) !bool {
    try web_worker.std_out.print("WebSocket opened\n", .{});
    if (web_worker.open_socket) |open_socket| {
        _ = websocket.sendText(open_socket, "open_orderbook:BTC/USD");
    }
    return true;
}

// fn onMessageCallback(web_worker: *WebSocketWebWorker(SharedData), message: []const u8) !bool {
//     try web_worker.std_out.print("Received message: {s}\n", .{message});
//     const orderbook = parseOrderbook(web_worker.allocator, message) catch |err| {
//         try web_worker.std_err.print("Failed to parse orderbook data: {s}\n", .{@errorName(err)});
//         return error.FailedToParseOrderbook;
//     };
//     try web_worker.std_out.print("Parsed orderbook: {s}\n", .{orderbook.ticker});
//     // try web_worker.std_out.print("Parsed orderbook: {s}\n", .{orderbook.ticker});

//     // if (self.windows.?.get(ob.ticker)) |window| {
//     //     if (window.popen) {
//     //         window.orderbook = ob;
//     //     } else {
//     //         self.allocator.free(window.open_message);
//     //         self.allocator.destroy(window);
//     //         _ = self.windows.?.remove(ob.ticker);
//     //         // TODO This is still dangling
//     //         self.tcp_client.?.write(window.close_message);
//     //     }
//     // } else {}
//     return true;
// }

fn onMessageCallback(web_worker: *WebSocketWebWorker(SharedData), message: []const u8) !bool {
    web_worker.std_out.print("Received message ({d} bytes): ", .{message.len}) catch unreachable;
    for (message[0..@min(message.len, 50)]) |byte| {
        web_worker.std_out.print("{x:0>2} ", .{byte}) catch unreachable;
    }
    web_worker.std_out.print("\n", .{}) catch unreachable;
    const orderbook = parseOrderbook(std.heap.c_allocator, message) catch {
        try web_worker.std_out.print("Failed\n", .{});
        return true;
    };
    // _ = web_worker;
    _ = orderbook;
    // web_worker.std_out.print("Parsed orderbook: {s}\n", .{orderbook.ticker}) catch {
    //     return true;
    // };
    return true;
}

fn onErrorCallback(web_worker: *WebSocketWebWorker(SharedData)) !bool {
    _ = web_worker;
    return true;
}

fn onCloseCallback(web_worker: *WebSocketWebWorker(SharedData), code: u16, reason: []const u8) !bool {
    _ = web_worker;
    _ = code;
    _ = reason;
    return true;
}
pub fn main() !void {
    const allocator = std.heap.c_allocator;
    var shared = SharedData{
        .orderbook_windows = try OrderbookWindows.init(allocator),
    };

    // Create web worker
    const ww = try WebSocketWebWorker(SharedData).init(
        std.heap.c_allocator,
        "ws://127.0.0.1:8081",
        &shared,
        workerEntrypoint,
        .{
            .on_open_cb = onOpenCallback,
            .on_message_cb = onMessageCallback,
            .on_error_cb = onErrorCallback,
            .on_close_cb = onCloseCallback,
        },
    );
    defer std.heap.c_allocator.destroy(ww);

    // Main thread loop
    var e = try engine.Engine.init(.{
        .width = 1024,
        .height = 768,
    });
    defer e.deinit();

    while (e.startRender()) {
        defer e.endRender();
        imgui.igShowDemoWindow(null);
    }
}
