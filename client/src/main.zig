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
        web_worker.shared_data.orderbook_windows = try OrderbookWindows.init(web_worker.allocator, open_socket);
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
    const orderbook = parseOrderbook(std.heap.c_allocator, message) catch |err| {
        try web_worker.std_out.print("Failed {any}\n", .{err});
        return true;
    };
    try web_worker.shared_data.orderbook_windows.updateOrderbook(orderbook.ticker, orderbook);
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
        .orderbook_windows = undefined,
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
        // imgui.igShowDemoWindow(null);
        const tickers = [_][]const u8{ "ETH/USD", "BTC/USD", "XRP/USD", "DOGE/USD", "SUI/USD", "USDC/USD", "SOL/USD", "PEPE/USD", "ADA/USD", "WIF/USD", "EUR/USD", "FARTCOIN/USD", "AVAX/USD", "LTC/USD", "XLM/USD", "TRUMP/USD" };
        if (imgui.igBeginMainMenuBar()) {
            defer imgui.igEndMainMenuBar();
            if (imgui.igBeginMenu("Orderbook", true)) {
                for (tickers) |ticker| {
                    const c_str = try std.fmt.allocPrintZ(allocator, "{s}\r\n", .{ticker});
                    defer allocator.free(c_str);
                    if (imgui.igMenuItem_Bool(c_str, null, false, true)) {
                        try shared.orderbook_windows.openWindow(ticker);
                    }
                }
                imgui.igEndMenu();
            }
        }
        shared.orderbook_windows.plot() catch unreachable;
    }
}
